import Foundation
import SQLite3

// MARK: - Data Models

struct SessionHistory: Codable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let projectPath: String
    let gitBranch: String?
    let gitRepo: String?
    
    // Recovery data - for reopening terminal sessions
    let sessionId: String
    let pid: String
    let command: String
    let arguments: [String]
    let terminal: String
    let tty: String
    let windowTitle: String
    let lastSeen: Date?
    let exitCode: Int32?
    let exitReason: String?
    
    // Performance metrics
    let peakCPU: Double
    let avgCPU: Double
    let peakMemory: Double
    let avgMemory: Double
    
    // Interaction metrics
    let messageCount: Int
    let filesModified: Int
    let linesAdded: Int
    let linesRemoved: Int
    let errorsCount: Int
    
    // Tool usage
    let toolUsage: [String: Int]
    
    var duration: TimeInterval {
        guard let endTime = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return endTime.timeIntervalSince(startTime)
    }
    
    // Recovery utility
    var fullCommand: String {
        if arguments.isEmpty {
            return command
        }
        return "\(command) \(arguments.joined(separator: " "))"
    }
    
    var isRecoverable: Bool {
        return !command.isEmpty && !sessionId.isEmpty && !pid.isEmpty
    }
}

struct SessionMetrics {
    var cpuSamples: [Double] = []
    var memorySamples: [Double] = []
    var toolCounts: [String: Int] = [:]
    var filesModified: Set<String> = []
    var linesAdded: Int = 0
    var linesRemoved: Int = 0
    var messageCount: Int = 0
    var errorCount: Int = 0
    
    var avgCPU: Double {
        guard !cpuSamples.isEmpty else { return 0 }
        return cpuSamples.reduce(0, +) / Double(cpuSamples.count)
    }
    
    var peakCPU: Double {
        return cpuSamples.max() ?? 0
    }
    
    var avgMemory: Double {
        guard !memorySamples.isEmpty else { return 0 }
        return memorySamples.reduce(0, +) / Double(memorySamples.count)
    }
    
    var peakMemory: Double {
        return memorySamples.max() ?? 0
    }
}

// MARK: - Database Manager

class SessionDatabase {
    static let shared = SessionDatabase()
    private var db: OpaquePointer?
    private let dbPath: String
    private let databaseQueue = DispatchQueue(label: "com.claudenavigator.database", qos: .utility)
    
    private init() {
        // Store database in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                  in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeNavigator", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, 
                                               withIntermediateDirectories: true)
        
        dbPath = appDir.appendingPathComponent("sessions.db").path
        print("📊 Database path: \(dbPath)")
        openDatabase()
        createTables()
    }
    
    deinit {
        // Ensure WAL checkpoint before closing
        executeSQL("PRAGMA wal_checkpoint(TRUNCATE);")
        sqlite3_close_v2(db)
    }
    
    // Helper method for extensions to get database connection
    internal func getDatabase() -> OpaquePointer? {
        return db
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Unable to open database at \(dbPath)")
        } else {
            print("✅ Database opened successfully at \(dbPath)")
            // Enable WAL mode to prevent corruption from multiple processes
            enableWALMode()
            // Check database integrity
            checkDatabaseIntegrity()
        }
    }
    
    private func enableWALMode() {
        executeSQL("PRAGMA journal_mode=WAL;")
        executeSQL("PRAGMA synchronous=FULL;")  // Changed from NORMAL to FULL for better durability
        executeSQL("PRAGMA cache_size=10000;")
        executeSQL("PRAGMA temp_store=memory;")
        executeSQL("PRAGMA wal_autocheckpoint=100;")  // Auto-checkpoint after 100 pages
        executeSQL("PRAGMA busy_timeout=5000;")  // Wait up to 5 seconds for locks
        print("✅ Database configured with WAL mode and corruption protection")
    }
    
    private func checkDatabaseIntegrity() {
        var statement: OpaquePointer?
        let sql = "PRAGMA integrity_check;"
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let result = String(cString: sqlite3_column_text(statement, 0))
                if result != "ok" {
                    print("⚠️ Database integrity check failed: \(result)")
                    print("🔄 Attempting to repair database...")
                    // Try to vacuum the database
                    executeSQL("VACUUM;")
                } else {
                    print("✅ Database integrity check passed")
                }
            }
        }
        sqlite3_finalize(statement)
    }
    
    private func createTables() {
        // First migrate existing table if needed
        migrateSessionHistoryForRecovery()
        
        let createSessionTable = """
            CREATE TABLE IF NOT EXISTS session_history (
                id TEXT PRIMARY KEY,
                start_time REAL NOT NULL,
                end_time REAL,
                project_path TEXT NOT NULL,
                git_branch TEXT,
                git_repo TEXT,
                session_id TEXT,
                pid TEXT,
                command TEXT,
                arguments TEXT,
                terminal TEXT,
                tty TEXT,
                window_title TEXT,
                last_seen REAL,
                exit_code INTEGER,
                exit_reason TEXT,
                peak_cpu REAL DEFAULT 0,
                avg_cpu REAL DEFAULT 0,
                peak_memory REAL DEFAULT 0,
                avg_memory REAL DEFAULT 0,
                message_count INTEGER DEFAULT 0,
                files_modified INTEGER DEFAULT 0,
                lines_added INTEGER DEFAULT 0,
                lines_removed INTEGER DEFAULT 0,
                errors_count INTEGER DEFAULT 0,
                created_at REAL DEFAULT (strftime('%s', 'now'))
            );
        """
        
        let createToolUsageTable = """
            CREATE TABLE IF NOT EXISTS tool_usage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                usage_count INTEGER DEFAULT 0,
                FOREIGN KEY (session_id) REFERENCES session_history(id)
            );
        """
        
        let createIndices = """
            CREATE INDEX IF NOT EXISTS idx_session_start_time ON session_history(start_time);
            CREATE INDEX IF NOT EXISTS idx_session_project ON session_history(project_path);
            CREATE INDEX IF NOT EXISTS idx_tool_session ON tool_usage(session_id);
        """
        
        executeSQL(createSessionTable)
        executeSQL(createToolUsageTable)
        executeSQL(createIndices)
    }
    
    private func migrateSessionHistoryForRecovery() {
        // Check if migration is needed by seeing if session_id column exists
        let checkColumnSql = "PRAGMA table_info(session_history)"
        
        guard let db = db else { return }
        
        var statement: OpaquePointer?
        var hasSessionId = false
        
        if sqlite3_prepare_v2(db, checkColumnSql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let columnName = sqlite3_column_text(statement, 1) {
                    let name = String(cString: columnName)
                    if name == "session_id" {
                        hasSessionId = true
                        break
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        
        if !hasSessionId {
            print("🔧 Migrating session_history table to include recovery fields...")
            
            let migrationSqls = [
                "ALTER TABLE session_history ADD COLUMN session_id TEXT",
                "ALTER TABLE session_history ADD COLUMN pid TEXT", 
                "ALTER TABLE session_history ADD COLUMN command TEXT",
                "ALTER TABLE session_history ADD COLUMN arguments TEXT",
                "ALTER TABLE session_history ADD COLUMN terminal TEXT",
                "ALTER TABLE session_history ADD COLUMN tty TEXT",
                "ALTER TABLE session_history ADD COLUMN window_title TEXT",
                "ALTER TABLE session_history ADD COLUMN last_seen REAL",
                "ALTER TABLE session_history ADD COLUMN exit_code INTEGER",
                "ALTER TABLE session_history ADD COLUMN exit_reason TEXT"
            ]
            
            for sql in migrationSqls {
                _executeSQL(sql)
            }
            
            print("✅ Session history migration completed")
        }
    }
    
    internal func executeSQL(_ sql: String) {
        databaseQueue.sync {
            self._executeSQL(sql)
        }
    }
    
    private func _executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        
        guard db != nil else {
            print("❌ Database connection is nil")
            return
        }
        
        // Retry mechanism for database locked errors
        var retryCount = 0
        let maxRetries = 3
        
        repeat {
            let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
            
            if prepareResult == SQLITE_OK {
                let stepResult = sqlite3_step(statement)
                if stepResult == SQLITE_DONE || stepResult == SQLITE_ROW {
                    print("✅ SQL executed successfully")
                    sqlite3_finalize(statement)
                    return
                } else if stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
                    print("⚠️ Database busy, retrying... (attempt \(retryCount + 1)/\(maxRetries))")
                    sqlite3_finalize(statement)
                    Thread.sleep(forTimeInterval: 0.1)
                    retryCount += 1
                    continue
                } else {
                    print("❌ SQL execution failed: \(String(cString: sqlite3_errmsg(db)))")
                    sqlite3_finalize(statement)
                    return
                }
            } else if prepareResult == SQLITE_BUSY || prepareResult == SQLITE_LOCKED {
                print("⚠️ Database busy during prepare, retrying... (attempt \(retryCount + 1)/\(maxRetries))")
                Thread.sleep(forTimeInterval: 0.1)
                retryCount += 1
                continue
            } else {
                print("❌ SQL preparation failed: \(String(cString: sqlite3_errmsg(db)))")
                sqlite3_finalize(statement)
                return
            }
        } while retryCount < maxRetries
        
        print("❌ SQL operation failed after \(maxRetries) retries")
    }
    
    // MARK: - CRUD Operations
    
    func saveSession(_ session: SessionHistory) {
        // Use transaction for atomicity
        executeSQL("BEGIN IMMEDIATE TRANSACTION;")

        let sql = """
            INSERT OR REPLACE INTO session_history 
            (id, start_time, end_time, project_path, git_branch, git_repo,
             session_id, pid, command, arguments, terminal, tty, window_title,
             last_seen, exit_code, exit_reason,
             peak_cpu, avg_cpu, peak_memory, avg_memory,
             message_count, files_modified, lines_added, lines_removed, errors_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            // Use Swift string binding that properly handles memory
            let idString = session.id.uuidString as NSString
            sqlite3_bind_text(statement, 1, idString.utf8String, -1, nil)
            
            sqlite3_bind_double(statement, 2, session.startTime.timeIntervalSince1970)
            
            if let endTime = session.endTime {
                sqlite3_bind_double(statement, 3, endTime.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            
            let projectPath = session.projectPath as NSString
            sqlite3_bind_text(statement, 4, projectPath.utf8String, -1, nil)
            
            if let branch = session.gitBranch {
                let branchString = branch as NSString
                sqlite3_bind_text(statement, 5, branchString.utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            
            if let repo = session.gitRepo {
                let repoString = repo as NSString
                sqlite3_bind_text(statement, 6, repoString.utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            // Recovery fields
            let sessionIdString = session.sessionId as NSString
            sqlite3_bind_text(statement, 7, sessionIdString.utf8String, -1, nil)
            
            let pidString = session.pid as NSString
            sqlite3_bind_text(statement, 8, pidString.utf8String, -1, nil)
            
            let commandString = session.command as NSString
            sqlite3_bind_text(statement, 9, commandString.utf8String, -1, nil)
            
            let argumentsJson = try? JSONEncoder().encode(session.arguments)
            if let argumentsData = argumentsJson {
                let argumentsString = String(data: argumentsData, encoding: .utf8)! as NSString
                sqlite3_bind_text(statement, 10, argumentsString.utf8String, -1, nil)
            } else {
                sqlite3_bind_text(statement, 10, "[]", -1, nil)
            }
            
            let terminalString = session.terminal as NSString
            sqlite3_bind_text(statement, 11, terminalString.utf8String, -1, nil)
            
            let ttyString = session.tty as NSString
            sqlite3_bind_text(statement, 12, ttyString.utf8String, -1, nil)
            
            let windowTitleString = session.windowTitle as NSString
            sqlite3_bind_text(statement, 13, windowTitleString.utf8String, -1, nil)
            
            if let lastSeen = session.lastSeen {
                sqlite3_bind_double(statement, 14, lastSeen.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 14)
            }
            
            if let exitCode = session.exitCode {
                sqlite3_bind_int(statement, 15, exitCode)
            } else {
                sqlite3_bind_null(statement, 15)
            }
            
            if let exitReason = session.exitReason {
                let exitReasonString = exitReason as NSString
                sqlite3_bind_text(statement, 16, exitReasonString.utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 16)
            }
            
            // Performance metrics
            sqlite3_bind_double(statement, 17, session.peakCPU)
            sqlite3_bind_double(statement, 18, session.avgCPU)
            sqlite3_bind_double(statement, 19, session.peakMemory)
            sqlite3_bind_double(statement, 20, session.avgMemory)
            
            sqlite3_bind_int(statement, 21, Int32(session.messageCount))
            sqlite3_bind_int(statement, 22, Int32(session.filesModified))
            sqlite3_bind_int(statement, 23, Int32(session.linesAdded))
            sqlite3_bind_int(statement, 24, Int32(session.linesRemoved))
            sqlite3_bind_int(statement, 25, Int32(session.errorsCount))
            
            if sqlite3_step(statement) == SQLITE_DONE {
                // Save tool usage
                saveToolUsage(sessionId: session.id, toolUsage: session.toolUsage)
                print("✅ Session saved with recovery data: \(session.id) / \(session.sessionId)")
            } else {
                print("❌ Failed to save session: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)

        saveToolUsage(sessionId: session.id, toolUsage: session.toolUsage)

        // Commit transaction
        executeSQL("COMMIT;")

        // Periodic checkpoint to prevent WAL from growing too large
        if Int.random(in: 0..<10) == 0 {
            executeSQL("PRAGMA wal_checkpoint(TRUNCATE);")
        }
    }

    private func saveToolUsage(sessionId: UUID, toolUsage: [String: Int]) {
        let sql = "INSERT INTO tool_usage (session_id, tool_name, usage_count) VALUES (?, ?, ?)"
        
        for (tool, count) in toolUsage {
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                let idString = sessionId.uuidString as NSString
                sqlite3_bind_text(statement, 1, idString.utf8String, -1, nil)
                
                let toolString = tool as NSString
                sqlite3_bind_text(statement, 2, toolString.utf8String, -1, nil)
                
                sqlite3_bind_int(statement, 3, Int32(count))
                
                sqlite3_step(statement)
            }
            
            sqlite3_finalize(statement)
        }
    }
    
    func getRecentSessions(limit: Int = 50) -> [SessionHistory] {
        let sql = """
            SELECT * FROM session_history 
            ORDER BY start_time DESC 
            LIMIT ?
        """
        
        var sessions: [SessionHistory] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let session = parseSessionRow(statement) {
                    sessions.append(session)
                } else {
                    print("⚠️ Failed to parse session row")
                }
            }
        } else {
            print("❌ Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        print("📊 getRecentSessions found \(sessions.count) sessions")
        return sessions
    }
    
    func getRecentSessions(limit: Int = 50, projectPath: String?) -> [SessionHistory] {
        var sql: String
        
        if let projectPath = projectPath {
            // If specific path requested, just get sessions for that path
            sql = """
                SELECT * FROM session_history 
                WHERE end_time IS NOT NULL AND project_path = ?
                ORDER BY end_time DESC 
                LIMIT ?
            """
        } else {
            // Get the most recent session for each unique project path
            // This prevents showing duplicate sessions for the same project
            sql = """
                SELECT * FROM session_history
                WHERE id IN (
                    SELECT id FROM (
                        SELECT id, project_path,
                               ROW_NUMBER() OVER (PARTITION BY project_path ORDER BY end_time DESC) as rn
                        FROM session_history
                        WHERE end_time IS NOT NULL
                    ) WHERE rn = 1
                )
                ORDER BY end_time DESC
                LIMIT ?
            """
        }
        
        var sessions: [SessionHistory] = []
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            var bindIndex = 1
            
            if let projectPath = projectPath {
                let pathString = projectPath as NSString
                sqlite3_bind_text(statement, Int32(bindIndex), pathString.utf8String, -1, nil)
                bindIndex += 1
            }
            
            sqlite3_bind_int(statement, Int32(bindIndex), Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                if let session = parseSessionRow(statement) {
                    sessions.append(session)
                } else {
                    print("⚠️ Failed to parse session row")
                }
            }
        } else {
            print("❌ Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        print("📊 getRecentSessions(projectPath: \(projectPath ?? "nil")) found \(sessions.count) sessions")
        return sessions
    }
    
    func markSessionEnded(sessionId: String, exitCode: Int32? = nil, exitReason: String? = nil) {
        let sql = """
            UPDATE session_history 
            SET end_time = ?, exit_code = ?, exit_reason = ?
            WHERE session_id = ?
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            
            if let exitCode = exitCode {
                sqlite3_bind_int(statement, 2, exitCode)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            
            if let exitReason = exitReason {
                let reasonString = exitReason as NSString
                sqlite3_bind_text(statement, 3, reasonString.utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            
            let sessionIdString = sessionId as NSString
            sqlite3_bind_text(statement, 4, sessionIdString.utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("✅ Session marked as ended: \(sessionId)")
            } else {
                print("❌ Failed to mark session as ended: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    func saveSessionCommand(sessionId: String, command: String, arguments: [String]) {
        let sql = """
            UPDATE session_history 
            SET command = ?, arguments = ?
            WHERE session_id = ?
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let commandString = command as NSString
            sqlite3_bind_text(statement, 1, commandString.utf8String, -1, nil)
            
            let argumentsJson = try? JSONEncoder().encode(arguments)
            if let argumentsData = argumentsJson {
                let argumentsString = String(data: argumentsData, encoding: .utf8)! as NSString
                sqlite3_bind_text(statement, 2, argumentsString.utf8String, -1, nil)
            } else {
                sqlite3_bind_text(statement, 2, "[]", -1, nil)
            }
            
            let sessionIdString = sessionId as NSString
            sqlite3_bind_text(statement, 3, sessionIdString.utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("✅ Session command updated: \(sessionId) -> \(command)")
            } else {
                print("❌ Failed to update session command: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    func updateSessionPresence(sessionId: String) {
        let sql = """
            UPDATE session_history 
            SET last_seen = ?
            WHERE session_id = ?
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
            
            let sessionIdString = sessionId as NSString
            sqlite3_bind_text(statement, 2, sessionIdString.utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                // Success, but don't log every presence update to avoid spam
            } else {
                print("❌ Failed to update session presence: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)
    }
    
    private func parseSessionRow(_ statement: OpaquePointer?) -> SessionHistory? {
        guard let idString = sqlite3_column_text(statement, 0),
              let id = UUID(uuidString: String(cString: idString)) else { 
            print("❌ Failed to parse session ID")
            return nil 
        }
        
        let startTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let endTimeInterval = sqlite3_column_double(statement, 2)
        let endTime = endTimeInterval > 0 ? Date(timeIntervalSince1970: endTimeInterval) : nil
        
        let projectPath = String(cString: sqlite3_column_text(statement, 3))
        let gitBranch = sqlite3_column_text(statement, 4).map { String(cString: $0) }
        let gitRepo = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        
        // Recovery fields
        let sessionId = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
        let pid = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
        let command = sqlite3_column_text(statement, 8).map { String(cString: $0) } ?? ""
        
        let argumentsJson = sqlite3_column_text(statement, 9).map { String(cString: $0) } ?? "[]"
        let arguments = (try? JSONDecoder().decode([String].self, from: argumentsJson.data(using: .utf8)!)) ?? []
        
        let terminal = sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? ""
        let tty = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? ""
        let windowTitle = sqlite3_column_text(statement, 12).map { String(cString: $0) } ?? ""
        
        let lastSeenInterval = sqlite3_column_double(statement, 13)
        let lastSeen = lastSeenInterval > 0 ? Date(timeIntervalSince1970: lastSeenInterval) : nil
        
        let exitCodeValue = sqlite3_column_int(statement, 14)
        let exitCode = exitCodeValue != 0 ? Int32(exitCodeValue) : nil
        
        let exitReason = sqlite3_column_text(statement, 15).map { String(cString: $0) }
        
        // Performance metrics
        let peakCPU = sqlite3_column_double(statement, 16)
        let avgCPU = sqlite3_column_double(statement, 17)
        let peakMemory = sqlite3_column_double(statement, 18)
        let avgMemory = sqlite3_column_double(statement, 19)
        
        let messageCount = Int(sqlite3_column_int(statement, 20))
        let filesModified = Int(sqlite3_column_int(statement, 21))
        let linesAdded = Int(sqlite3_column_int(statement, 22))
        let linesRemoved = Int(sqlite3_column_int(statement, 23))
        let errorsCount = Int(sqlite3_column_int(statement, 24))
        
        // Load tool usage
        let toolUsage = loadToolUsage(for: id)
        
        return SessionHistory(
            id: id,
            startTime: startTime,
            endTime: endTime,
            projectPath: projectPath,
            gitBranch: gitBranch,
            gitRepo: gitRepo,
            sessionId: sessionId,
            pid: pid,
            command: command,
            arguments: arguments,
            terminal: terminal,
            tty: tty,
            windowTitle: windowTitle,
            lastSeen: lastSeen,
            exitCode: exitCode,
            exitReason: exitReason,
            peakCPU: peakCPU,
            avgCPU: avgCPU,
            peakMemory: peakMemory,
            avgMemory: avgMemory,
            messageCount: messageCount,
            filesModified: filesModified,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            errorsCount: errorsCount,
            toolUsage: toolUsage
        )
    }
    
    private func loadToolUsage(for sessionId: UUID) -> [String: Int] {
        let sql = "SELECT tool_name, usage_count FROM tool_usage WHERE session_id = ?"
        var toolUsage: [String: Int] = [:]
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let idString = sessionId.uuidString as NSString
            sqlite3_bind_text(statement, 1, idString.utf8String, -1, nil)
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let toolName = String(cString: sqlite3_column_text(statement, 0))
                let count = Int(sqlite3_column_int(statement, 1))
                toolUsage[toolName] = count
            }
        }
        
        sqlite3_finalize(statement)
        return toolUsage
    }
    
    // MARK: - Analytics
    
    func debugDatabaseContents() {
        let sql = "SELECT COUNT(*) FROM session_history"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(statement, 0))
                print("🔍 DEBUG: Total rows in session_history: \(count)")
            }
        }
        sqlite3_finalize(statement)
        
        // Check sessions with calculated duration
        let sql2 = """
            SELECT id, project_path,
                   CASE 
                       WHEN end_time IS NULL THEN strftime('%s', 'now') - start_time 
                       ELSE end_time - start_time 
                   END as duration,
                   avg_cpu, avg_memory
            FROM session_history 
            ORDER BY start_time DESC 
            LIMIT 3
        """
        if sqlite3_prepare_v2(db, sql2, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let path = String(cString: sqlite3_column_text(statement, 1))
                let duration = sqlite3_column_double(statement, 2)
                let cpu = sqlite3_column_double(statement, 3)
                let mem = sqlite3_column_double(statement, 4)
                print("🔍 DEBUG: Session \(id.prefix(8))... in \(path.split(separator: "/").last ?? "?") - \(Int(duration))s, CPU:\(String(format: "%.1f", cpu))%, Mem:\(String(format: "%.0f", mem))MB")
            }
        }
        sqlite3_finalize(statement)
    }
    
    func getSessionStats(for projectPath: String? = nil, days: Int? = 30) -> SessionStats {
        // For active sessions (end_time IS NULL), use current time - start_time
        var sql = """
            SELECT COUNT(*), 
                   SUM(CASE 
                       WHEN end_time IS NULL THEN strftime('%s', 'now') - start_time 
                       ELSE end_time - start_time 
                   END),
                   AVG(avg_cpu), 
                   AVG(avg_memory) 
            FROM session_history
        """
        
        var conditions: [String] = []
        
        // Add time filter if days is specified
        if let days = days {
            conditions.append("start_time > ?")
        }
        
        if let projectPath = projectPath {
            conditions.append("project_path = ?")
        }
        
        // Add WHERE clause if there are conditions
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        
        var stats = SessionStats()
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            var bindIndex: Int32 = 1
            
            // Bind time filter if specified
            if let days = days {
                let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
                sqlite3_bind_double(statement, bindIndex, cutoffDate.timeIntervalSince1970)
                bindIndex += 1
            }
            
            // Bind project path if specified
            if let projectPath = projectPath {
                let pathString = projectPath as NSString
                sqlite3_bind_text(statement, bindIndex, pathString.utf8String, -1, nil)
            }
            
            if sqlite3_step(statement) == SQLITE_ROW {
                stats.totalSessions = Int(sqlite3_column_int(statement, 0))
                stats.totalDuration = sqlite3_column_double(statement, 1)
                stats.avgCPU = sqlite3_column_double(statement, 2)
                stats.avgMemory = sqlite3_column_double(statement, 3)
                
                print("📊 Stats: sessions=\(stats.totalSessions), duration=\(stats.totalDuration)s, avgCPU=\(stats.avgCPU)%, avgMem=\(stats.avgMemory)MB")
            }
        }
        
        sqlite3_finalize(statement)
        return stats
    }
    
    // MARK: - Session Lookup Methods
    
    /// Find existing session by PID - returns the database ID to avoid creating duplicates
    func findExistingSessionId(forPid pid: String) -> UUID? {
        let sql = "SELECT id FROM session_history WHERE pid = ? AND end_time IS NULL ORDER BY start_time DESC LIMIT 1"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let pidString = pid as NSString
            sqlite3_bind_text(statement, 1, pidString.utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                if let idString = sqlite3_column_text(statement, 0) {
                    let idStr = String(cString: idString)
                    sqlite3_finalize(statement)
                    return UUID(uuidString: idStr)
                }
            }
        }
        
        sqlite3_finalize(statement)
        return nil
    }
    
    /// Find most recent session for a project path - reuse if ended recently (within 5 minutes)
    func findReusableSessionId(forPath path: String) -> UUID? {
        // Look for sessions that ended recently (within 5 minutes) for the same path
        let sql = """
            SELECT id, end_time FROM session_history 
            WHERE project_path = ? 
            AND end_time IS NOT NULL 
            AND datetime(end_time) > datetime('now', '-5 minutes')
            ORDER BY end_time DESC 
            LIMIT 1
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let pathString = path as NSString
            sqlite3_bind_text(statement, 1, pathString.utf8String, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_ROW {
                if let idString = sqlite3_column_text(statement, 0) {
                    let idStr = String(cString: idString)
                    sqlite3_finalize(statement)
                    print("♻️ Reusing existing session \(idStr) for path \(path)")
                    return UUID(uuidString: idStr)
                }
            }
        }
        
        sqlite3_finalize(statement)
        return nil
    }
}

struct SessionStats {
    var totalSessions: Int = 0
    var totalDuration: TimeInterval = 0
    var avgCPU: Double = 0
    var avgMemory: Double = 0
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}