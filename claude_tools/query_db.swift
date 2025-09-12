#!/usr/bin/env swift

import Foundation
import SQLite3

func queryDatabase() {
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
    
    // Query all sessions with deduplication analysis
    let query = """
        SELECT 
            id,
            start_time,
            end_time,
            project_path,
            git_branch,
            git_repo,
            session_id,
            pid,
            command,
            arguments,
            terminal,
            tty,
            window_title,
            last_seen,
            exit_code,
            exit_reason,
            peak_cpu,
            avg_cpu,
            peak_memory,
            avg_memory,
            message_count,
            files_modified,
            lines_added,
            lines_removed,
            errors_count,
            tool_usage
        FROM session_history 
        ORDER BY start_time DESC
        LIMIT 20
    """
    
    var statement: OpaquePointer?
    
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        print("=== RECENT 20 SESSIONS ===")
        print("ID | Start | End | Project | Branch | SessionId | PID | Terminal | TTY")
        print("---|-------|-----|---------|--------|-----------|-----|----------|----")
        
        var sessionCount = 0
        var uniqueProjects: Set<String> = []
        var uniquePids: Set<String> = []
        var duplicatePids: Set<String> = []
        var pidCounts: [String: Int] = [:]
        
        while sqlite3_step(statement) == SQLITE_ROW {
            sessionCount += 1
            
            let id = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            let startTime = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let endTime = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let projectPath = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let gitBranch = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let sessionId = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
            let pid = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            let terminal = sqlite3_column_text(statement, 10).map { String(cString: $0) } ?? ""
            let tty = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? ""
            
            // Track project names for deduplication analysis
            let projectName = projectPath.split(separator: "/").last.map(String.init) ?? projectPath
            uniqueProjects.insert(projectName)
            
            // Track PID duplicates
            pidCounts[pid, default: 0] += 1
            if pidCounts[pid]! > 1 {
                duplicatePids.insert(pid)
            }
            
            // Format start time to be shorter
            let shortStartTime = String(startTime.prefix(16))
            let hasEnded = !endTime.isEmpty ? "✓" : "○"
            
            print("\(String(id.prefix(8))) | \(shortStartTime) | \(hasEnded) | \(String(projectName.prefix(10))) | \(String(gitBranch.prefix(8))) | \(String(sessionId.prefix(8))) | \(String(pid.prefix(8))) | \(String(terminal.prefix(8))) | \(String(tty.prefix(8)))")
        }
        
        print("\n=== ANALYSIS ===")
        print("Total sessions in last 20: \(sessionCount)")
        print("Unique projects: \(uniqueProjects.count) - \(Array(uniqueProjects).joined(separator: ", "))")
        print("Duplicate PIDs found: \(duplicatePids.count)")
        
        if !duplicatePids.isEmpty {
            print("PIDs with multiple entries:")
            for pid in duplicatePids.sorted() {
                print("  - PID \(pid): \(pidCounts[pid]!) entries")
            }
        }
    } else {
        print("SELECT statement could not be prepared")
    }
    
    sqlite3_finalize(statement)
    
    // Count total sessions
    let countQuery = "SELECT COUNT(*) FROM session_history"
    if sqlite3_prepare_v2(db, countQuery, -1, &statement, nil) == SQLITE_OK {
        if sqlite3_step(statement) == SQLITE_ROW {
            let totalCount = sqlite3_column_int(statement, 0)
            print("\nTotal sessions in database: \(totalCount)")
        }
    }
    sqlite3_finalize(statement)
}

queryDatabase()