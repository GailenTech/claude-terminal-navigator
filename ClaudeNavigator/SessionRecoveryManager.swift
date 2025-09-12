//
//  SessionRecoveryManager.swift
//  ClaudeNavigator
//
//  Manages session recovery by reopening Terminal with original commands
//

import Foundation
import AppKit
import SQLite3

class SessionRecoveryManager {
    static let shared = SessionRecoveryManager()
    
    private let database = SessionDatabase.shared
    
    private init() {}
    
    // MARK: - Recovery Methods
    
    func recoverSession(_ history: SessionHistory) {
        print("🔄 Recovering session: \(history.sessionId ?? "unknown")")
        
        // Build the command to execute
        let fullCommand = history.fullCommand
        
        // Change to the project directory first, then run the command
        let cdCommand = "cd \"\(history.projectPath)\""
        let combinedCommand = "\(cdCommand) && \(fullCommand)"
        
        // Open Terminal with the command
        openTerminalWithCommand(combinedCommand)
        
        // Log the recovery attempt
        logRecoveryAttempt(history)
    }
    
    func recoverSessionById(_ sessionId: String) {
        // Find the session in history
        let recentSessions = getRecentSessions(limit: 100)
        
        guard let session = recentSessions.first(where: { $0.sessionId == sessionId }) else {
            print("❌ Session not found in history: \(sessionId)")
            showAlert(title: "Session Not Found",
                     message: "The session could not be found in history.")
            return
        }
        
        recoverSession(session)
    }
    
    // MARK: - Terminal Integration
    
    private func openTerminalWithCommand(_ command: String) {
        // Escape special characters for AppleScript
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        tell application "Terminal"
            activate
            set newTab to do script "\(escapedCommand)"
            set current settings of newTab to settings set "Pro"
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let result = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                print("❌ Failed to open Terminal: \(error)")
                showAlert(title: "Recovery Failed",
                         message: "Could not open Terminal with the session command.")
            } else {
                print("✅ Terminal opened with recovered session")
            }
        }
    }
    
    // MARK: - Recent Sessions
    
    func getRecentSessions(limit: Int = 20) -> [SessionHistory] {
        return database.getRecentSessions(limit: limit, projectPath: nil)
    }
    
    func getRecentSessionsAsClaudeSessions(limit: Int = 20) -> [ClaudeSession] {
        let recentSessions = getRecentSessions(limit: limit)
        return recentSessions.compactMap { history in
            // Only convert sessions that have recovery data
            guard !history.sessionId.isEmpty,
                  !history.pid.isEmpty else {
                return nil
            }
            
            var session = ClaudeSession(
                pid: history.pid,
                tty: history.tty,
                terminal: history.terminal,
                sessionId: history.sessionId,
                windowTitle: history.windowTitle,
                startTime: ISO8601DateFormatter().string(from: history.startTime),
                workingDir: history.projectPath,
                dirName: URL(fileURLWithPath: history.projectPath).lastPathComponent,
                parentPid: "0"
            )
            
            session.gitBranch = history.gitBranch
            session.cachedCPU = history.avgCPU
            session.cachedMemory = history.avgMemory
            session.gitRepo = history.gitRepo
            session.lastUpdateTime = history.lastSeen ?? history.endTime ?? history.startTime
            
            return session
        }
    }
    
    // MARK: - Session Lifecycle
    
    func sessionStarted(_ session: ClaudeSession, command: String, arguments: [String] = []) {
        // Try to reuse existing session for the same project path
        let sessionId = SessionDatabase.shared.findReusableSessionId(forPath: session.workingDir) ?? UUID()
        
        // Create a SessionHistory record with recovery data
        let history = SessionHistory(
            id: sessionId,
            startTime: Date(),
            endTime: nil,
            projectPath: session.workingDir,
            gitBranch: session.gitBranch,
            gitRepo: extractRepoName(from: session.workingDir),
            sessionId: session.sessionId,
            pid: session.pid,
            command: command,
            arguments: arguments,
            terminal: session.terminal,
            tty: session.tty,
            windowTitle: session.windowTitle,
            lastSeen: Date(),
            exitCode: nil,
            exitReason: nil,
            peakCPU: session.cachedCPU ?? 0,
            avgCPU: session.cachedCPU ?? 0,
            peakMemory: session.cachedMemory ?? 0,
            avgMemory: session.cachedMemory ?? 0,
            messageCount: 0,
            filesModified: 0,
            linesAdded: 0,
            linesRemoved: 0,
            errorsCount: 0,
            toolUsage: [:]
        )
        
        database.saveSession(history)
        print("📝 Session started and saved to history: \(session.sessionId)")
    }
    
    func sessionEnded(_ sessionId: String, exitCode: Int32? = nil, crashed: Bool = false) {
        let exitReason = crashed ? "crash" : "normal"
        database.markSessionEnded(sessionId: sessionId, exitCode: exitCode, exitReason: exitReason)
        
        print("📝 Session ended: \(sessionId) (reason: \(exitReason))")
    }
    
    // MARK: - Command Capture
    
    func captureCommand(for session: ClaudeSession) {
        // Try to get the command from the process
        let pid = Int32(session.pid) ?? 0
        
        if let command = getProcessCommand(pid: pid) {
            database.saveSessionCommand(sessionId: session.sessionId,
                                       command: command.command,
                                       arguments: command.arguments)
            print("📝 Captured command for session \(session.sessionId): \(command.command)")
        }
    }
    
    private func getProcessCommand(pid: Int32) -> (command: String, arguments: [String])? {
        // Use ps to get the full command line
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", String(pid), "-o", "command="]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                return nil
            }
            
            // Parse the command line
            let components = output.components(separatedBy: " ")
            guard !components.isEmpty else { return nil }
            
            // First component is the command, rest are arguments
            let command = components[0]
            let arguments = Array(components.dropFirst())
            
            // Only capture if it's actually a claude command
            if command.contains("claude") || components.contains("claude") {
                return (command: "claude", arguments: arguments.filter { !$0.contains("claude") })
            }
            
            return nil
        } catch {
            print("❌ Failed to get process command: \(error)")
            return nil
        }
    }
    
    // MARK: - Utilities
    
    private func logRecoveryAttempt(_ history: SessionHistory) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let startTimeStr = formatter.string(from: history.startTime)
        
        let durationStr: String
        if let endTime = history.endTime {
            let duration = endTime.timeIntervalSince(history.startTime)
            let hours = Int(duration) / 3600
            let minutes = Int(duration) % 3600 / 60
            let seconds = Int(duration) % 60
            
            if hours > 0 {
                durationStr = String(format: "%dh %dm %ds", hours, minutes, seconds)
            } else if minutes > 0 {
                durationStr = String(format: "%dm %ds", minutes, seconds)
            } else {
                durationStr = String(format: "%ds", seconds)
            }
        } else {
            durationStr = "Unknown"
        }
        
        print("""
        🔄 Recovery Attempt:
           Session: \(history.sessionId.isEmpty ? "unknown" : history.sessionId)
           Project: \(URL(fileURLWithPath: history.projectPath).lastPathComponent)
           Command: \(history.fullCommand)
           Original Start: \(startTimeStr)
           Duration: \(durationStr)
        """)
    }
    
    private func extractRepoName(from path: String) -> String? {
        // Extract repo name from path like /Users/x/Projects/my-repo
        let components = path.split(separator: "/")
        
        // Look for .git directory to identify repo root
        var currentPath = ""
        for component in components {
            currentPath += "/\(component)"
            let gitPath = currentPath + "/.git"
            if FileManager.default.fileExists(atPath: gitPath) {
                return String(component)
            }
        }
        
        // Fallback to last component
        return components.last.map(String.init)
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // MARK: - Cleanup
    
    func cleanupOldHistory(daysToKeep: Int = 30) {
        let cutoffDate = Date().addingTimeInterval(-Double(daysToKeep * 24 * 60 * 60))
        
        let sql = """
            DELETE FROM session_history
            WHERE end_time IS NOT NULL
            AND end_time < ?
        """
        
        guard let db = database.getDatabase() else { return }
        // Don't close - this is a shared database instance
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, cutoffDate.timeIntervalSince1970)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                let deletedRows = sqlite3_changes(db)
                print("🧹 Cleaned up \(deletedRows) old history entries")
            }
        }
        
        sqlite3_finalize(statement)
    }
}