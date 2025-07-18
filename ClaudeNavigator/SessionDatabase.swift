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
        sqlite3_close(db)
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("❌ Unable to open database at \(dbPath)")
        } else {
            print("✅ Database opened successfully at \(dbPath)")
        }
    }
    
    private func createTables() {
        let createSessionTable = """
            CREATE TABLE IF NOT EXISTS session_history (
                id TEXT PRIMARY KEY,
                start_time REAL NOT NULL,
                end_time REAL,
                project_path TEXT NOT NULL,
                git_branch TEXT,
                git_repo TEXT,
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
    
    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_DONE {
                print("✅ SQL executed successfully")
            } else {
                print("❌ SQL execution failed: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("❌ SQL preparation failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
    }
    
    // MARK: - CRUD Operations
    
    func saveSession(_ session: SessionHistory) {
        let sql = """
            INSERT OR REPLACE INTO session_history 
            (id, start_time, end_time, project_path, git_branch, git_repo,
             peak_cpu, avg_cpu, peak_memory, avg_memory,
             message_count, files_modified, lines_added, lines_removed, errors_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            
            sqlite3_bind_double(statement, 7, session.peakCPU)
            sqlite3_bind_double(statement, 8, session.avgCPU)
            sqlite3_bind_double(statement, 9, session.peakMemory)
            sqlite3_bind_double(statement, 10, session.avgMemory)
            
            sqlite3_bind_int(statement, 11, Int32(session.messageCount))
            sqlite3_bind_int(statement, 12, Int32(session.filesModified))
            sqlite3_bind_int(statement, 13, Int32(session.linesAdded))
            sqlite3_bind_int(statement, 14, Int32(session.linesRemoved))
            sqlite3_bind_int(statement, 15, Int32(session.errorsCount))
            
            if sqlite3_step(statement) == SQLITE_DONE {
                // Save tool usage
                saveToolUsage(sessionId: session.id, toolUsage: session.toolUsage)
                print("✅ Session saved: \(session.id)")
            } else {
                print("❌ Failed to save session: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        
        sqlite3_finalize(statement)
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
        
        let peakCPU = sqlite3_column_double(statement, 6)
        let avgCPU = sqlite3_column_double(statement, 7)
        let peakMemory = sqlite3_column_double(statement, 8)
        let avgMemory = sqlite3_column_double(statement, 9)
        
        let messageCount = Int(sqlite3_column_int(statement, 10))
        let filesModified = Int(sqlite3_column_int(statement, 11))
        let linesAdded = Int(sqlite3_column_int(statement, 12))
        let linesRemoved = Int(sqlite3_column_int(statement, 13))
        let errorsCount = Int(sqlite3_column_int(statement, 14))
        
        // Load tool usage
        let toolUsage = loadToolUsage(for: id)
        
        return SessionHistory(
            id: id,
            startTime: startTime,
            endTime: endTime,
            projectPath: projectPath,
            gitBranch: gitBranch,
            gitRepo: gitRepo,
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