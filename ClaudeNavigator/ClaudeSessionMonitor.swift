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
    var gitRepo: String?
    var lastUpdateTime: Date?
    
    // Attention tracking (not persisted)
    var needsAttention: Bool = false
    var lastCPUReadings: [Double] = []
    var lastStateChange: Date?
    var attentionManuallyClearedAt: Date? // Track when user manually cleared attention
    
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
    
    // Format session age (time since last update)
    var formattedAge: String {
        guard let updateTime = lastUpdateTime else { return "" }
        let duration = Date().timeIntervalSince(updateTime)
        
        if duration < 60 {
            return "\(Int(duration))s ago"
        } else if duration < 3600 {
            return "\(Int(duration / 60))m ago"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(duration / 86400)
            return "\(days)d ago"
        }
    }
    
    // MARK: - Attention Detection Methods
    
    mutating func updateCPUReading(_ cpu: Double) {
        // Keep only last 5 readings for transition detection
        lastCPUReadings.append(cpu)
        if lastCPUReadings.count > 5 {
            lastCPUReadings.removeFirst()
        }
    }
    
    var hasTransitionedToIdle: Bool {
        // Need at least 3 readings to detect transition
        guard lastCPUReadings.count >= 3 else { return false }
        
        let recent = Array(lastCPUReadings.suffix(3))
        
        // Check if recent readings show idle (≤ 1%)
        let recentIsIdle = recent.allSatisfy { $0 <= 1.0 }
        
        // Look for any earlier high activity in the history
        let hasEarlierActivity = lastCPUReadings.count > 3 && 
                                lastCPUReadings.prefix(lastCPUReadings.count - 3).contains { $0 > 1.0 }
        
        // Debug logging
        if lastCPUReadings.count >= 3 {
            print("🔍 Transition check: readings=\(lastCPUReadings), recentIdle=\(recentIsIdle), hadActivity=\(hasEarlierActivity)")
        }
        
        return recentIsIdle && hasEarlierActivity
    }
    
    var shouldTriggerAttentionAlert: Bool {
        guard hasTransitionedToIdle else { return false }
        
        // Check if enough time has passed since the transition
        if let lastChange = lastStateChange {
            return Date().timeIntervalSince(lastChange) >= 5.0
        }
        
        return false
    }
}

// MARK: - Session Monitor

class ClaudeSessionMonitor {
    // Store discovered sessions in memory
    private var knownSessions: [String: ClaudeSession] = [:] // PID -> Session
    private let sessionQueue = DispatchQueue(label: "com.claudenavigator.sessions")
    private let tracker = SessionTracker()
    private let focusDetector = FocusDetector.shared
    
    // Prevent concurrent session updates
    private var isUpdating = false
    private let updateQueue = DispatchQueue(label: "com.claudenavigator.update", qos: .userInitiated)
    private var updateCounter = 0
    
    init() {
        print("🚀 Initializing standalone ClaudeSessionMonitor")
    }
    
    func getActiveSessions() async throws -> [ClaudeSession] {
        return try await withCheckedThrowingContinuation { continuation in
            updateQueue.async {
                Task {
                    do {
                        let result = try await self.performSessionUpdate()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // Synchronous version for UI operations
    func getActiveSessions() -> [ClaudeSession] {
        return sessionQueue.sync { Array(knownSessions.values) }
    }
    
    private func performSessionUpdate() async throws -> [ClaudeSession] {
        // Increment update counter
        updateCounter += 1
        
        // Prevent concurrent updates
        guard !self.isUpdating else {
            print("⚠️ Update already in progress, skipping concurrent call")
            return self.sessionQueue.sync { Array(self.knownSessions.values) }
        }
        
        self.isUpdating = true
        defer { self.isUpdating = false }
        
        // Find all Claude processes
        let claudeProcesses = try await self.findClaudeProcesses()
        
        // Convert processes to sessions
        var sessions: [ClaudeSession] = []
        
        for processInfo in claudeProcesses {
            if let session = await self.createSession(from: processInfo) {
                sessions.append(session)
                
                // Note: Don't store in knownSessions yet - we need to preserve existing data first
            }
        }
        
        // NOTE: Don't cleanup dead sessions yet - we need them to detect session ends
        // await self.cleanupDeadSessionsFromMemory()
        
        // Check for ended sessions BEFORE updating knownSessions
        let activePIDs = sessions.map { $0.pid }
        let trackedPIDs = self.sessionQueue.sync { Array(self.knownSessions.keys) }
        
        print("🔍 Checking for ended sessions. Active: \(activePIDs.count), Tracked: \(trackedPIDs.count)")
        
        for pid in trackedPIDs {
            if !activePIDs.contains(pid) {
                print("⚠️ Session with PID \(pid) is no longer active")
                // Session has ended
                if let endedSession = self.sessionQueue.sync(execute: { self.knownSessions[pid] }) {
                    // Mark session as ended in history
                    SessionRecoveryManager.shared.sessionEnded(endedSession.sessionId)
                    print("📝 Session ended: \(endedSession.sessionId) (PID: \(pid))")
                    
                    // Remove from knownSessions
                    self.sessionQueue.sync {
                        self.knownSessions.removeValue(forKey: pid)
                    }
                } else {
                    print("❓ Could not find session data for PID \(pid)")
                }
                
                self.tracker.stopTracking(pid: pid)
            }
        }
        
        // Update CPU, memory and Git info for all sessions
        var updatedSessions: [ClaudeSession] = []
        for var session in sessions {
            // Get existing session data for transition tracking
            let existingSession = self.sessionQueue.sync { self.knownSessions[session.pid] }
            if let existing = existingSession {
                session.lastCPUReadings = existing.lastCPUReadings
                session.lastStateChange = existing.lastStateChange
                session.needsAttention = existing.needsAttention
                session.attentionManuallyClearedAt = existing.attentionManuallyClearedAt
            }
        
            // Get CPU usage
            if let cpu = await self.getCPUUsage(for: session.pid) {
                session.cachedCPU = cpu
                session.updateCPUReading(cpu)
                print("📊 PID \(session.pid) CPU: \(cpu)% (readings: \(session.lastCPUReadings.count))")
            }
            
            // Get memory usage
            if let memory = await self.getMemoryUsage(for: session.pid) {
                session.cachedMemory = memory
            }
            // Get Git info
            if let branch = await self.getGitBranch(for: session.workingDir) {
                session.gitBranch = branch
            }
            if let status = await self.getGitStatus(for: session.workingDir) {
                session.gitStatus = status
            }
            
            // Check for attention needed transition
            await self.processAttentionLogic(for: &session)
            
            // Update metrics tracking
            self.tracker.updateMetrics(for: session)
            
            updatedSessions.append(session)
            
            // Store updated session back in knownSessions for next iteration
            self.sessionQueue.sync {
                self.knownSessions[session.pid] = session
            }
            
            // Update presence in database periodically (every 5 updates)
            if self.updateCounter % 5 == 0 {
                SessionDatabase.shared.updateSessionPresence(sessionId: session.sessionId)
            }
        }
        
        // Now cleanup any remaining dead sessions that weren't in current active list
        self.sessionQueue.sync {
            let currentActivePIDs = Set(activePIDs)
            let staleEntries = self.knownSessions.keys.filter { !currentActivePIDs.contains($0) }
            for stalePid in staleEntries {
                print("🧹 Cleaning up stale session entry: \(stalePid)")
                self.knownSessions.removeValue(forKey: stalePid)
            }
        }
        
        return updatedSessions
    }
    
    private func findClaudeProcesses() async throws -> [(pid: String, ppid: String, tty: String, startTime: String, command: String)] {
        // Find all processes named "claude" - use separate ps and awk to get proper command
        let output = try await ShellExecutor.run(
            "ps aux | grep -E 'claude\\s' | grep -v grep | grep -v claude-nav | grep -v ClaudeNavigator | awk '{print $2}'"
        )
        
        var processes: [(pid: String, ppid: String, tty: String, startTime: String, command: String)] = []
        
        let pids = output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        // For each PID, get detailed info
        for pid in pids {
            // Get process details including full command
            if let detailOutput = try? await ShellExecutor.run(
                "ps -o pid,ppid,tty,lstart,args -p \(pid) | tail -1"
            ) {
                let components = detailOutput.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
                if components.count >= 8 {
                    let ppid = String(components[1])
                    let tty = String(components[2])
                    // lstart format: "Thu Jul 17 13:25:12 2025"
                    let startTime = components[3..<8].joined(separator: " ")
                    // Rest is the command and arguments
                    let command = components.count > 8 ? String(components[8...].joined(separator: " ")) : "claude"
                    
                    processes.append((pid: pid, ppid: ppid, tty: tty, startTime: startTime, command: command))
                    print("🔍 Found Claude process: PID=\(pid), TTY=\(tty)")
                }
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
        
        // Check if this is a new session (not in knownSessions)
        let isNewSession = sessionQueue.sync { knownSessions[pid] == nil }
        
        if isNewSession {
            // This is a new session - capture command and save to history
            var command = "claude"
            var arguments: [String] = []
            
            // First try to get command from session file if it exists
            if let sessionData = await getSessionFileData(for: pid) {
                command = sessionData.command
                arguments = sessionData.arguments
            } else {
                // Fallback to parsing the process command
                let commandParts = processInfo.command.components(separatedBy: " ")
                command = commandParts.first ?? "claude"
                arguments = Array(commandParts.dropFirst())
            }
            
            // Save session to history with command
            SessionRecoveryManager.shared.sessionStarted(session, command: command, arguments: arguments)
            
            // IMPORTANT: Add to knownSessions immediately so we can track when it ends
            sessionQueue.sync {
                knownSessions[pid] = session
            }
            
            print("📝 New session detected and saved: \(sessionId) with command: \(command) \(arguments.joined(separator: " "))")
        }
        
        return session
    }
    
    private func getSessionFileData(for pid: String) async -> (command: String, arguments: [String])? {
        // Try to read the session file created by claude-nav wrapper
        let sessionPath = "\(NSHomeDirectory())/.claude/sessions/\(pid).json"
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sessionPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            return nil
        }
        
        let arguments = (json["arguments"] as? [String]) ?? []
        return (command: command, arguments: arguments)
    }
    
    private func getWorkingDirectory(for pid: String) async -> String? {
        // Try multiple methods to get working directory
        
        // Method 1: Try pwdx (most reliable)
        do {
            let output = try await ShellExecutor.run("pwdx \(pid) 2>/dev/null")
            let components = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", maxSplits: 1)
            if components.count == 2 {
                let cwd = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !cwd.isEmpty && !cwd.contains("No such process") {
                    return cwd
                }
            }
        } catch {
            // pwdx failed, try next method
        }
        
        // Method 2: Try lsof with better error handling
        do {
            let output = try await ShellExecutor.run("lsof -p \(pid) 2>/dev/null | grep 'cwd' | awk '{print $NF}'")
            let cwd = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cwd.isEmpty && !cwd.contains("usage:") && !cwd.contains("lsof:") && !cwd.hasPrefix("-") {
                return cwd
            }
        } catch {
            // lsof failed, try next method
        }
        
        // Method 3: Try /proc-style approach (fallback)
        do {
            let output = try await ShellExecutor.run("readlink /proc/\(pid)/cwd 2>/dev/null || echo ''")
            let cwd = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cwd.isEmpty && !cwd.contains("No such file") {
                return cwd
            }
        } catch {
            // All methods failed
        }
        
        print("⚠️ Could not determine working directory for PID \(pid)")
        return nil
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
    
    // MARK: - Attention Logic
    
    private func processAttentionLogic(for session: inout ClaudeSession) async {
        print("🔧 Processing attention logic for PID \(session.pid), CPU readings count: \(session.lastCPUReadings.count)")
        
        // Debug: Print CPU readings for debugging
        if session.lastCPUReadings.count >= 3 {
            print("🧪 Session \(session.pid) CPU history: \(session.lastCPUReadings)")
        } else {
            print("⏳ Session \(session.pid) needs more readings (has \(session.lastCPUReadings.count), needs 3+)")
        }
        
        // Check if attention was manually cleared recently (within last 10 seconds)
        let wasManuallyClearedRecently = session.attentionManuallyClearedAt?.timeIntervalSinceNow ?? -Double.infinity > -10
        if wasManuallyClearedRecently {
            let secondsAgo = Int(abs(session.attentionManuallyClearedAt?.timeIntervalSinceNow ?? 0))
            print("🚫 Session \(session.pid) attention was manually cleared \(secondsAgo)s ago - skipping auto-attention logic")
            return
        }
        
        // Check if session has transitioned to idle
        if session.hasTransitionedToIdle {
            // Mark the transition time if not already set
            if session.lastStateChange == nil {
                session.lastStateChange = Date()
                print("🔄 Session \(session.pid) (\(session.dirName)) transitioned to idle")
            }
            
            // Check if enough time has passed and session is not focused
            if session.shouldTriggerAttentionAlert {
                print("⏰ Session \(session.pid) ready for attention check (5s passed)")
                let isFocused = await focusDetector.isSessionCurrentlyFocused(session)
                
                if !isFocused && !session.needsAttention {
                    session.needsAttention = true
                    print("⚠️ Session \(session.pid) (\(session.dirName)) needs attention - not focused")
                } else if isFocused {
                    print("👀 Session \(session.pid) (\(session.dirName)) is focused - skipping attention alert")
                } else if session.needsAttention {
                    print("🔄 Session \(session.pid) already flagged for attention")
                }
            } else {
                print("⏳ Session \(session.pid) transitioned but waiting for 5s delay")
            }
        } else {
            // Reset attention state if session becomes active again
            if session.needsAttention && session.isActive {
                session.needsAttention = false
                session.lastStateChange = nil
                session.attentionManuallyClearedAt = nil // Clear manual flag when naturally resolved
                print("✅ Session \(session.pid) (\(session.dirName)) became active - clearing attention flag")
            }
        }
    }
    
    /// Clear attention flag for a specific session (called when user interacts with it)
    func clearAttentionFlag(for pid: String) {
        sessionQueue.sync {
            if var session = knownSessions[pid] {
                session.needsAttention = false
                session.lastStateChange = nil
                session.attentionManuallyClearedAt = Date() // Mark when user manually cleared
                knownSessions[pid] = session
                print("👆 User interacted with session \(pid) - clearing attention flag and marking as manually cleared")
            } else {
                print("⚠️ Attempted to clear attention flag for unknown session: \(pid)")
            }
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