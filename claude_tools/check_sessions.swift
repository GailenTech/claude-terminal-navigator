#!/usr/bin/env swift

import Foundation
import SQLite3

func checkSessions() {
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    let dbPath = homeDirectory.appendingPathComponent(".claude/sessions.db").path
    
    var db: OpaquePointer?
    
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
        print("Unable to open database at \(dbPath)")
        return
    }
    
    defer {
        sqlite3_close(db)
    }
    
    // First, check what tables exist
    print("=== CHECKING DATABASE STRUCTURE ===")
    let tableQuery = "SELECT name FROM sqlite_master WHERE type='table'"
    var statement: OpaquePointer?
    
    if sqlite3_prepare_v2(db, tableQuery, -1, &statement, nil) == SQLITE_OK {
        print("Tables in database:")
        while sqlite3_step(statement) == SQLITE_ROW {
            if let tableName = sqlite3_column_text(statement, 0) {
                print("  - \(String(cString: tableName))")
            }
        }
    }
    sqlite3_finalize(statement)
    
    // Check active sessions (end_time IS NULL)
    print("\n=== ACTIVE SESSIONS (end_time IS NULL) ===")
    let activeQuery = """
        SELECT id, pid, project_path, start_time 
        FROM session_history 
        WHERE end_time IS NULL
        ORDER BY start_time DESC
    """
    
    if sqlite3_prepare_v2(db, activeQuery, -1, &statement, nil) == SQLITE_OK {
        var count = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            count += 1
            let id = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let pid = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let path = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let start = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            
            let projectName = path.split(separator: "/").last.map(String.init) ?? path
            print("  \(String(id.prefix(8))) | PID: \(pid) | \(projectName) | Started: \(String(start.prefix(16)))")
        }
        print("Total active sessions: \(count)")
    } else {
        print("Failed to query active sessions")
    }
    sqlite3_finalize(statement)
    
    // Check completed sessions (end_time IS NOT NULL)
    print("\n=== COMPLETED SESSIONS (end_time IS NOT NULL) ===")
    let completedQuery = """
        SELECT id, pid, project_path, start_time, end_time 
        FROM session_history 
        WHERE end_time IS NOT NULL
        ORDER BY end_time DESC
        LIMIT 10
    """
    
    if sqlite3_prepare_v2(db, completedQuery, -1, &statement, nil) == SQLITE_OK {
        var count = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            count += 1
            let id = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let pid = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let path = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let start = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let end = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            
            let projectName = path.split(separator: "/").last.map(String.init) ?? path
            print("  \(String(id.prefix(8))) | PID: \(pid) | \(projectName) | Ended: \(String(end.prefix(16)))")
        }
        print("Showing last \(count) completed sessions")
    } else {
        print("Failed to query completed sessions")
    }
    sqlite3_finalize(statement)
    
    // Count total sessions
    print("\n=== SESSION COUNTS ===")
    let countQuery = """
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN end_time IS NULL THEN 1 END) as active,
            COUNT(CASE WHEN end_time IS NOT NULL THEN 1 END) as completed
        FROM session_history
    """
    
    if sqlite3_prepare_v2(db, countQuery, -1, &statement, nil) == SQLITE_OK {
        if sqlite3_step(statement) == SQLITE_ROW {
            let total = sqlite3_column_int(statement, 0)
            let active = sqlite3_column_int(statement, 1)
            let completed = sqlite3_column_int(statement, 2)
            print("Total sessions: \(total)")
            print("Active sessions: \(active)")
            print("Completed sessions: \(completed)")
        }
    }
    sqlite3_finalize(statement)
}

checkSessions()