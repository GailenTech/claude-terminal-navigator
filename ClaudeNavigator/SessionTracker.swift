import Foundation

// MARK: - Session Tracker

class SessionTracker {
    private var activeSessions: [String: TrackedSession] = [:]  // PID -> TrackedSession
    private let updateQueue = DispatchQueue(label: "com.claudenavigator.sessiontracker")
    
    struct TrackedSession {
        let pid: String
        let sessionId: UUID
        let startTime: Date
        var projectPath: String
        var gitBranch: String?
        var gitRepo: String?
        var metrics: SessionMetrics
        
        init(pid: String, projectPath: String) {
            self.pid = pid
            self.sessionId = UUID()
            self.startTime = Date()
            self.projectPath = projectPath
            self.metrics = SessionMetrics()
        }
    }
    
    // MARK: - Session Lifecycle
    
    func startTracking(session: ClaudeSession) {
        updateQueue.async { [weak self] in
            let tracked = TrackedSession(
                pid: session.pid,
                projectPath: session.workingDir
            )
            
            self?.activeSessions[session.pid] = tracked
            print("📊 Started tracking session: \(session.pid) in \(session.dirName)")
        }
    }
    
    func updateMetrics(for session: ClaudeSession) {
        updateQueue.async { [weak self] in
            guard var tracked = self?.activeSessions[session.pid] else {
                // New session, start tracking
                self?.startTracking(session: session)
                return
            }
            
            // Update performance metrics
            if let cpu = session.cachedCPU {
                tracked.metrics.cpuSamples.append(cpu)
            }
            
            if let memory = session.cachedMemory {
                tracked.metrics.memorySamples.append(memory)
            }
            
            // Update git info
            tracked.gitBranch = session.gitBranch
            tracked.gitRepo = self?.extractRepoName(from: session.workingDir)
            
            self?.activeSessions[session.pid] = tracked
        }
    }
    
    func stopTracking(pid: String) {
        updateQueue.async { [weak self] in
            guard let tracked = self?.activeSessions[pid] else { return }
            
            // Create final session history
            let history = SessionHistory(
                id: tracked.sessionId,
                startTime: tracked.startTime,
                endTime: Date(),
                projectPath: tracked.projectPath,
                gitBranch: tracked.gitBranch,
                gitRepo: tracked.gitRepo,
                peakCPU: tracked.metrics.peakCPU,
                avgCPU: tracked.metrics.avgCPU,
                peakMemory: tracked.metrics.peakMemory,
                avgMemory: tracked.metrics.avgMemory,
                messageCount: tracked.metrics.messageCount,
                filesModified: tracked.metrics.filesModified.count,
                linesAdded: tracked.metrics.linesAdded,
                linesRemoved: tracked.metrics.linesRemoved,
                errorsCount: tracked.metrics.errorCount,
                toolUsage: tracked.metrics.toolCounts
            )
            
            // Save to database
            SessionDatabase.shared.saveSession(history)
            
            // Remove from active tracking
            self?.activeSessions.removeValue(forKey: pid)
            print("📊 Stopped tracking session: \(pid) - Duration: \(history.duration)s")
        }
    }
    
    // MARK: - Output Parsing
    
    func parseClaudeOutput(_ output: String, for pid: String) {
        updateQueue.async { [weak self] in
            guard var tracked = self?.activeSessions[pid] else { return }
            
            // Detect tool usage
            let toolPatterns: [(pattern: String, tool: String)] = [
                ("Calling.*Bash.*tool", "Bash"),
                ("Calling.*Read.*tool", "Read"),
                ("Calling.*Write.*tool", "Write"),
                ("Calling.*Edit.*tool", "Edit"),
                ("Calling.*MultiEdit.*tool", "MultiEdit"),
                ("Calling.*Grep.*tool", "Grep"),
                ("Calling.*Glob.*tool", "Glob"),
                ("Calling.*WebFetch.*tool", "WebFetch"),
                ("Calling.*WebSearch.*tool", "WebSearch"),
                ("Calling.*TodoWrite.*tool", "TodoWrite"),
                ("git commit", "Git Commit"),
                ("git push", "Git Push"),
                ("npm test|yarn test|pytest", "Test Run")
            ]
            
            for (pattern, tool) in toolPatterns {
                if output.range(of: pattern, options: .regularExpression) != nil {
                    tracked.metrics.toolCounts[tool, default: 0] += 1
                }
            }
            
            // Detect file modifications
            if output.contains("File.*updated") || output.contains("File created") {
                if let match = output.range(of: "/[^\\s]+", options: .regularExpression) {
                    let filePath = String(output[match])
                    tracked.metrics.filesModified.insert(filePath)
                }
            }
            
            // Detect line changes
            if let addMatch = output.range(of: "\\+(\\d+) insertions?", options: .regularExpression) {
                let numberStr = output[addMatch].replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                tracked.metrics.linesAdded += Int(numberStr) ?? 0
            }
            
            if let delMatch = output.range(of: "\\-(\\d+) deletions?", options: .regularExpression) {
                let numberStr = output[delMatch].replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                tracked.metrics.linesRemoved += Int(numberStr) ?? 0
            }
            
            // Detect errors
            if output.contains("error:") || output.contains("Error:") || output.contains("❌") {
                tracked.metrics.errorCount += 1
            }
            
            // Count messages
            if output.contains("Human:") || output.contains("Assistant:") {
                tracked.metrics.messageCount += 1
            }
            
            self?.activeSessions[pid] = tracked
        }
    }
    
    // MARK: - Analytics
    
    func getActiveSessionMetrics() -> [String: SessionMetrics] {
        updateQueue.sync {
            var result: [String: SessionMetrics] = [:]
            for (pid, tracked) in activeSessions {
                result[pid] = tracked.metrics
            }
            return result
        }
    }
    
    func getCurrentStats() -> (active: Int, totalCPU: Double, totalMemory: Double) {
        updateQueue.sync {
            let active = activeSessions.count
            let totalCPU = activeSessions.values
                .compactMap { $0.metrics.cpuSamples.last }
                .reduce(0, +)
            let totalMemory = activeSessions.values
                .compactMap { $0.metrics.memorySamples.last }
                .reduce(0, +)
            
            return (active, totalCPU, totalMemory)
        }
    }
    
    // MARK: - Helpers
    
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
}

// MARK: - Extension for Output Monitoring

extension SessionTracker {
    
    /// Monitor Claude's stdout/stderr for a given PID
    func startOutputMonitoring(for pid: String) {
        Task {
            do {
                // Use lsof to find the terminal's output
                let _ = try await ShellExecutor.run("lsof -p \(pid) 2>/dev/null | grep -E 'REG|CHR' | grep -v '.dylib' | awk '{print $NF}'")
                
                // Set up file monitoring
                // This is a placeholder - actual implementation would require
                // more sophisticated output capture, possibly using:
                // 1. dtrace/dtruss (requires elevated permissions)
                // 2. Intercepting terminal output
                // 3. Claude API integration for proper metrics
                
                print("📊 Would monitor output for PID \(pid)")
                
            } catch {
                print("❌ Failed to set up output monitoring: \(error)")
            }
        }
    }
}

