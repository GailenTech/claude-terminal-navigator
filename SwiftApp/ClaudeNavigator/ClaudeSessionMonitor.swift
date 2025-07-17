//
//  ClaudeSessionMonitor.swift
//  ClaudeNavigator
//
//  Session monitoring and management
//

import Foundation
import AppKit

// MARK: - Session Model

struct ClaudeSession: Codable {
    let pid: String
    let tty: String
    let terminal: String
    let sessionId: String
    let windowTitle: String
    let startTime: String
    let workingDir: String
    let dirName: String
    let parentPid: String
    
    // Cached values (not from JSON)
    var cachedCPU: Double?
    var cachedMemory: Double?
    
    // Coding keys to match JSON format
    enum CodingKeys: String, CodingKey {
        case pid
        case tty
        case terminal
        case sessionId = "session_id"
        case windowTitle = "window_title"
        case startTime = "start_time"
        case workingDir = "working_dir"
        case dirName = "dir_name"
        case parentPid = "parent_pid"
    }
    
    // Computed properties
    var isActive: Bool {
        // Lower threshold to 1% to catch more active processes
        return (cachedCPU ?? 0) > 1.0
    }
    
    var formattedDuration: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let startDate = formatter.date(from: startTime) else {
            // Try alternative format
            let alternativeFormatter = DateFormatter()
            alternativeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            guard let altDate = alternativeFormatter.date(from: startTime) else {
                return "Unknown"
            }
            return formatDuration(from: altDate)
        }
        
        return formatDuration(from: startDate)
    }
    
    private func formatDuration(from startDate: Date) -> String {
        let duration = Date().timeIntervalSince(startDate)
        
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Session Monitor

class ClaudeSessionMonitor {
    static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions")
    
    private let scriptsDirectory: String
    
    init() {
        // Get the actual path to scripts
        self.scriptsDirectory = "/Volumes/DevelopmentProjects/Claude/claude-terminal-navigator/bin"
    }
    
    func getActiveSessions() async throws -> [ClaudeSession] {
        var sessions: [ClaudeSession] = []
        
        // First cleanup dead sessions
        _ = await cleanupDeadSessions()
        
        // Check if sessions directory exists
        guard FileManager.default.fileExists(atPath: Self.sessionsDirectory.path) else {
            return []
        }
        
        // Read all session files
        let files = try FileManager.default.contentsOfDirectory(
            at: Self.sessionsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        
        // Process each file concurrently
        await withTaskGroup(of: ClaudeSession?.self) { group in
            for file in files {
                group.addTask {
                    await self.loadSession(from: file)
                }
            }
            
            for await session in group {
                if let session = session {
                    sessions.append(session)
                }
            }
        }
        
        // Update CPU and memory usage for all sessions
        var updatedSessions: [ClaudeSession] = []
        for var session in sessions {
            // Get CPU usage
            if let cpu = await getCPUUsage(for: session.pid) {
                session.cachedCPU = cpu
                print("📊 PID \(session.pid) CPU: \(cpu)%")
            }
            // Get memory usage
            if let memory = await getMemoryUsage(for: session.pid) {
                session.cachedMemory = memory
            }
            updatedSessions.append(session)
        }
        
        return updatedSessions
    }
    
    private func getCPUUsage(for pid: String) async -> Double? {
        do {
            let output = try await ShellExecutor.run("ps -p \(pid) -o %cpu=")
            // Handle both comma and dot as decimal separator
            let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                                   .replacingOccurrences(of: ",", with: ".")
            return Double(cleanOutput)
        } catch {
            return nil
        }
    }
    
    private func getMemoryUsage(for pid: String) async -> Double? {
        do {
            let output = try await ShellExecutor.run("ps -p \(pid) -o rss=")
            if let rssKB = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return Double(rssKB) / 1024.0
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func loadSession(from url: URL) async -> ClaudeSession? {
        do {
            let data = try Data(contentsOf: url)
            let session = try JSONDecoder().decode(ClaudeSession.self, from: data)
            
            // Check if process is still alive
            let isAlive = await isProcessAlive(pid: session.pid)
            return isAlive ? session : nil
        } catch {
            print("Error loading session from \(url): \(error)")
            return nil
        }
    }
    
    private func isProcessAlive(pid: String) async -> Bool {
        do {
            _ = try await ShellExecutor.run("kill -0 \(pid)")
            return true
        } catch {
            return false
        }
    }
    
    @discardableResult
    func cleanupDeadSessions() async -> String? {
        do {
            let output = try await ShellExecutor.runScript(
                "\(scriptsDirectory)/claude-cleanup"
            )
            return output
        } catch {
            print("Error cleaning up sessions: \(error)")
            return nil
        }
    }
}

// MARK: - Shell Executor

enum ShellError: Error {
    case executionFailed(String)
    case invalidOutput
}

class ShellExecutor {
    static func run(_ command: String, arguments: [String] = []) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            let pipe = Pipe()
            
            task.standardOutput = pipe
            task.standardError = pipe
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", command]
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ShellError.executionFailed(output))
                }
            }
            
            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    static func runScript(_ scriptPath: String, arguments: [String] = []) async throws -> String {
        let fullCommand = ([scriptPath] + arguments)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
        return try await run(fullCommand)
    }
}

// MARK: - Terminal Navigator

class TerminalNavigator {
    static func jumpToSession(session: ClaudeSession) async throws {
        let script = """
        on run
            set targetTTY to "\(session.tty)"
            set targetDir to "\(session.dirName)"
            
            try
                tell application "Terminal"
                    activate
                    set foundTab to false
                    
                    repeat with w from 1 to count of windows
                        try
                            set tabCount to count of tabs of window w
                            
                            repeat with t from 1 to tabCount
                                try
                                    if (tty of tab t of window w) is targetTTY then
                                        set frontmost of window w to true
                                        set selected tab of window w to tab t of window w
                                        set foundTab to true
                                        exit repeat
                                    end if
                                end try
                            end repeat
                        end try
                        
                        if foundTab then exit repeat
                    end repeat
                    
                    return foundTab
                end tell
            on error errMsg
                return false
            end try
        end run
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                throw ShellError.executionFailed(error.description)
            }
            
            // Show notification on success
            if result.booleanValue {
                await showNotification(title: "Claude Navigator", 
                                     message: "Jumped to \(session.dirName)")
            }
        }
    }
    
    static func jumpUsingScript(pid: String) async throws {
        let scriptsDir = "/Volumes/DevelopmentProjects/Claude/claude-terminal-navigator/bin"
        _ = try await ShellExecutor.runScript("\(scriptsDir)/claude-jump", arguments: [pid])
    }
    
    @MainActor
    private static func showNotification(title: String, message: String) {
        // Using newer UserNotifications framework would require more setup
        // For now, we'll use a simple approach
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}