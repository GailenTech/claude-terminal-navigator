//
//  FocusDetector.swift
//  ClaudeNavigator
//
//  Focus detection system for Terminal.app sessions
//

import Foundation
import AppKit

// MARK: - Focus Detector

class FocusDetector {
    static let shared = FocusDetector()
    
    private var cachedFocusedTTY: String?
    private var lastFocusCheck: Date = Date.distantPast
    private let cacheValidityDuration: TimeInterval = 1.0 // Cache for 1 second
    
    private init() {}
    
    /// Determines if a specific session is currently focused in Terminal.app
    func isSessionCurrentlyFocused(_ session: ClaudeSession) async -> Bool {
        let focusedTTY = await getCurrentlyFocusedTTY()
        return focusedTTY == session.tty
    }
    
    /// Gets the TTY of the currently focused Terminal tab
    private func getCurrentlyFocusedTTY() async -> String? {
        // Use cached value if still valid
        let now = Date()
        if now.timeIntervalSince(lastFocusCheck) < cacheValidityDuration,
           let cached = cachedFocusedTTY {
            return cached
        }
        
        // Check if Terminal is the frontmost application first
        guard await isTerminalFrontmost() else {
            cachedFocusedTTY = nil
            lastFocusCheck = now
            return nil
        }
        
        // Get the TTY of the currently selected tab in the front window
        let focusedTTY = await getFocusedTerminalTTY()
        
        // Update cache
        cachedFocusedTTY = focusedTTY
        lastFocusCheck = now
        
        return focusedTTY
    }
    
    /// Checks if Terminal.app is the frontmost application
    private func isTerminalFrontmost() async -> Bool {
        let script = """
        tell application "System Events"
            try
                set frontApp to name of first application process whose frontmost is true
                return frontApp is "Terminal"
            on error
                return false
            end try
        end tell
        """
        
        return await withCheckedContinuation { continuation in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let result = scriptObject.executeAndReturnError(&error)
                if error == nil {
                    let boolValue = result.booleanValue
                    continuation.resume(returning: boolValue)
                } else {
                    continuation.resume(returning: false)
                }
            } else {
                continuation.resume(returning: false)
            }
        }
    }
    
    /// Gets the TTY of the currently selected tab in Terminal.app's front window
    private func getFocusedTerminalTTY() async -> String? {
        let script = """
        tell application "Terminal"
            try
                # Get the selected tab of the front window
                set currentTab to selected tab of front window
                return tty of currentTab
            on error errMsg
                return ""
            end try
        end tell
        """
        
        return await withCheckedContinuation { continuation in
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let result = scriptObject.executeAndReturnError(&error)
                if error == nil, let ttyString = result.stringValue, !ttyString.isEmpty {
                    continuation.resume(returning: ttyString)
                } else {
                    continuation.resume(returning: nil)
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Clear the cache to force a fresh check on next call
    func invalidateCache() {
        cachedFocusedTTY = nil
        lastFocusCheck = Date.distantPast
    }
    
    /// Get debug information about current focus state
    func getDebugInfo() async -> String {
        let isTerminalFront = await isTerminalFrontmost()
        let focusedTTY = await getCurrentlyFocusedTTY()
        let cacheAge = Date().timeIntervalSince(lastFocusCheck)
        
        return """
        FocusDetector Debug Info:
        - Terminal is frontmost: \(isTerminalFront)
        - Focused TTY: \(focusedTTY ?? "none")
        - Cache age: \(String(format: "%.1f", cacheAge))s
        - Cache valid: \(cacheAge < cacheValidityDuration)
        """
    }
}