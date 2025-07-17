//
//  ClaudeSessionMonitor.swift
//  ClaudeNavigator
//
//  Session monitoring and management - Standalone version
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
    var gitBranch: String?
    var gitStatus: String?
    
    // Coding keys to match JSON format (kept for compatibility)
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
    // Store discovered sessions in memory
    private var knownSessions: [String: ClaudeSession] = [:] // PID -> Session
    private let sessionQueue = DispatchQueue(label: "com.claudenavigator.sessions")
    
    init() {
        print("🚀 Initializing standalone ClaudeSessionMonitor")
    }
    
    func getActiveSessions() async throws -> [ClaudeSession] {
        // Find all Claude processes
        let claudeProcesses = try await findClaudeProcesses()
        
        // Convert processes to sessions
        var sessions: [ClaudeSession] = []
        
        for processInfo in claudeProcesses {
            if let session = await createSession(from: processInfo) {
                sessions.append(session)
                
                // Store in known sessions
                sessionQueue.sync {
                    knownSessions[session.pid] = session
                }
            }
        }
        
        // Clean up dead sessions from memory
        await cleanupDeadSessionsFromMemory()
        
        // Update CPU, memory and Git info for all sessions
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
            // Get Git info
            if let branch = await getGitBranch(for: session.workingDir) {
                session.gitBranch = branch
            }
            if let status = await getGitStatus(for: session.workingDir) {
                session.gitStatus = status
            }
            updatedSessions.append(session)
        }
        
        return updatedSessions
    }
    
    private func findClaudeProcesses() async throws -> [(pid: String, ppid: String, tty: String, startTime: String, command: String)] {
        // Find all processes named "claude"
        let output = try await ShellExecutor.run(
            "ps -eo pid,ppid,tty,lstart,command | grep -E '/claude\\s*$|claude\\s*$' | grep -v grep | grep -v claude-nav | grep -v ClaudeNavigator"
        )
        
        var processes: [(pid: String, ppid: String, tty: String, startTime: String, command: String)] = []
        
        let lines = output.split(separator: "\n")
        for line in lines {
            let components = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            if components.count >= 7 {
                let pid = String(components[0])
                let ppid = String(components[1])
                let tty = String(components[2])
                // lstart format: "Thu Jul 17 13:25:12 2025"
                let startTime = components[3..<7].joined(separator: " ")
                let command = String(components[6])
                
                processes.append((pid: pid, ppid: ppid, tty: tty, startTime: startTime, command: command))
                print("🔍 Found Claude process: PID=\(pid), TTY=\(tty)")
            }
        }
        
        return processes
    }
    
    private func createSession(from processInfo: (pid: String, ppid: String, tty: String, startTime: String, command: String)) async -> ClaudeSession? {
        let pid = processInfo.pid
        
        // Get working directory
        guard let workingDir = await getWorkingDirectory(for: pid) else {
            print("❌ Could not get working directory for PID \(pid)")
            return nil
        }
        
        // Get terminal info
        let terminalInfo = await getTerminalInfo(for: pid, ppid: processInfo.ppid, tty: processInfo.tty)
        
        // Convert start time to ISO format
        let isoStartTime = convertToISOTime(processInfo.startTime)
        
        // Generate session ID
        let sessionId = UUID().uuidString
        
        // Create session
        let session = ClaudeSession(
            pid: pid,
            tty: processInfo.tty.hasPrefix("/dev/") ? processInfo.tty : "/dev/\(processInfo.tty)",
            terminal: terminalInfo.terminal,
            sessionId: sessionId,
            windowTitle: terminalInfo.windowTitle,
            startTime: isoStartTime,
            workingDir: workingDir,
            dirName: URL(fileURLWithPath: workingDir).lastPathComponent,
            parentPid: processInfo.ppid
        )
        
        return session
    }
    
    private func getWorkingDirectory(for pid: String) async -> String? {
        do {
            // Use lsof to get current working directory
            let output = try await ShellExecutor.run("lsof -p \(pid) | grep 'cwd' | awk '{print $NF}'")
            let cwd = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return cwd.isEmpty ? nil : cwd
        } catch {
            print("Error getting working directory for PID \(pid): \(error)")
            return nil
        }
    }
    
    private func getTerminalInfo(for pid: String, ppid: String, tty: String) async -> (terminal: String, windowTitle: String) {
        // Find terminal by traversing parent process chain
        var currentPid = ppid
        var terminal = "Unknown"
        
        for _ in 0..<10 { // Limit traversal depth
            do {
                let output = try await ShellExecutor.run("ps -p \(currentPid) -o comm=,ppid=")
                let components = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
                
                if components.count >= 1 {
                    let processName = String(components[0])
                    
                    if processName.contains("Terminal") {
                        terminal = "Apple_Terminal"
                        break
                    } else if processName.contains("iTerm") {
                        terminal = "iTerm2"
                        break
                    } else if processName.contains("Ghostty") || processName.contains("ghostty") {
                        terminal = "Ghostty"
                        break
                    }
                    
                    // Move to parent
                    if components.count >= 2 {
                        currentPid = String(components[1])
                    } else {
                        break
                    }
                }
            } catch {
                break
            }
        }
        
        // Get window title for Terminal.app
        var windowTitle = ""
        if terminal == "Apple_Terminal" {
            windowTitle = await getTerminalWindowTitle(for: tty) ?? ""
        }
        
        return (terminal: terminal, windowTitle: windowTitle)
    }
    
    private func getTerminalWindowTitle(for tty: String) async -> String? {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is "\(tty)" then
                            return name of w
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return ""
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            if error == nil, let title = result.stringValue {
                return title
            }
        }
        return nil
    }
    
    private func convertToISOTime(_ timeString: String) -> String {
        // Convert "Thu Jul 17 13:25:12 2025" to ISO format
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = formatter.date(from: timeString) {
            let isoFormatter = ISO8601DateFormatter()
            return isoFormatter.string(from: date)
        }
        
        // Fallback to current time if parsing fails
        return ISO8601DateFormatter().string(from: Date())
    }
    
    private func cleanupDeadSessionsFromMemory() async {
        var alivePids: Set<String> = []
        
        // Check which PIDs are still alive
        for (pid, _) in knownSessions {
            if await isProcessAlive(pid: pid) {
                alivePids.insert(pid)
            }
        }
        
        // Update known sessions
        sessionQueue.sync {
            knownSessions = knownSessions.filter { pid, _ in
                alivePids.contains(pid)
            }
        }
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
    
    private func getGitBranch(for workingDir: String) async -> String? {
        do {
            let output = try await ShellExecutor.run("cd '\(workingDir)' && git branch --show-current 2>/dev/null")
            let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return branch.isEmpty ? nil : branch
        } catch {
            return nil
        }
    }
    
    private func getGitStatus(for workingDir: String) async -> String? {
        do {
            let output = try await ShellExecutor.run("cd '\(workingDir)' && git status --porcelain 2>/dev/null")
            let statusLines = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if statusLines.isEmpty {
                return "clean"
            } else {
                let lineCount = statusLines.components(separatedBy: .newlines).count
                return "\(lineCount) changes"
            }
        } catch {
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
            _ = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                throw ShellError.executionFailed(error.description)
            }
            
            // Silent success - no notification needed
        }
    }
    
    static func jumpUsingScript(pid: String) async throws {
        // Fallback: Just activate Terminal app
        // The standalone version doesn't rely on external scripts
        _ = try await ShellExecutor.run("open -a Terminal")
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