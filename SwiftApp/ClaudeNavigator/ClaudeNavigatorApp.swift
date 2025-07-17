//
//  ClaudeNavigatorApp.swift
//  ClaudeNavigator
//
//  Created by Claude Terminal Navigator
//

import SwiftUI

@main
struct ClaudeNavigatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar apps don't need a window scene
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var sessionMonitor: ClaudeSessionMonitor!
    
    // Cache for performance
    private var lastActiveCount = 0
    private var lastWaitingCount = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 ClaudeNavigator starting...")
        
        // Hide dock icon for menu bar only app
        NSApp.setActivationPolicy(.accessory)
        print("✅ Activation policy set to accessory")
        
        // Create status bar item with variable length
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        print("✅ Status item created")
        
        // Initialize session monitor
        sessionMonitor = ClaudeSessionMonitor()
        
        // Build initial menu
        buildMenu()
        
        // Assign menu to status item
        statusItem.menu = menu
        
        if let button = statusItem.button {
            // Set initial icon
            button.title = "🤖"
            print("✅ Button configured with emoji title: \(button.title)")
        } else {
            print("❌ Failed to create status button!")
        }
        
        // Start refresh timer (5 seconds like xbar)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.refresh()
        }
        
        // Initial refresh
        print("🔄 Starting initial refresh...")
        refresh()
        
        print("✅ ClaudeNavigator fully initialized!")
    }
    
    func updateIcon(activeCount: Int, waitingCount: Int) {
        guard let button = statusItem.button else { return }
        
        // Only update if counts changed
        if activeCount == lastActiveCount && waitingCount == lastWaitingCount {
            return
        }
        
        lastActiveCount = activeCount
        lastWaitingCount = waitingCount
        
        let totalCount = activeCount + waitingCount
        
        DispatchQueue.main.async {
            // Very compact format to avoid notch issues
            if activeCount > 0 {
                button.title = "🤖\(activeCount)/\(totalCount)"
                button.toolTip = "\(activeCount) active, \(waitingCount) waiting"
            } else if waitingCount > 0 {
                button.title = "🤖0/\(totalCount)"
                button.toolTip = "All \(waitingCount) sessions waiting"
            } else {
                button.title = "🤖"
                button.toolTip = "No active Claude sessions"
            }
        }
    }
    
    func buildMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false
    }
    
    @objc func refresh() {
        Task {
            do {
                let sessions = try await sessionMonitor.getActiveSessions()
                await MainActor.run {
                    self.updateMenu(with: sessions)
                }
            } catch {
                print("Error refreshing sessions: \(error)")
            }
        }
    }
    
    func updateMenu(with sessions: [ClaudeSession]) {
        menu.removeAllItems()
        
        let activeSessions = sessions.filter { $0.isActive }
        let waitingSessions = sessions.filter { !$0.isActive }
        
        // Update icon
        updateIcon(activeCount: activeSessions.count, waitingCount: waitingSessions.count)
        
        // Header
        if activeSessions.count > 0 {
            let header = NSMenuItem(title: "Active Sessions: \(activeSessions.count)", 
                                  action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            
            let totalCPU = activeSessions.compactMap({ $0.cachedCPU }).reduce(0, +)
            if totalCPU > 0 {
                let cpuItem = NSMenuItem(title: "Total CPU: \(String(format: "%.1f", totalCPU))%", 
                                       action: nil, keyEquivalent: "")
                cpuItem.isEnabled = false
                menu.addItem(cpuItem)
            }
        } else if waitingSessions.count > 0 {
            let header = NSMenuItem(title: "Waiting Sessions: \(waitingSessions.count)", 
                                  action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        } else {
            let header = NSMenuItem(title: "No Active Sessions", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Sessions
        if !sessions.isEmpty {
            // Sort sessions: active first, then by CPU usage
            let sortedSessions = sessions.sorted { s1, s2 in
                if s1.isActive != s2.isActive {
                    return s1.isActive
                }
                return (s1.cachedCPU ?? 0) > (s2.cachedCPU ?? 0)
            }
            
            for session in sortedSessions {
                let icon = session.isActive ? "🟢" : "🟡"
                let title = "\(icon) \(session.dirName)"
                
                let sessionItem = NSMenuItem(title: title, 
                                           action: #selector(jumpToSession(_:)), 
                                           keyEquivalent: "")
                sessionItem.representedObject = session
                sessionItem.toolTip = session.workingDir
                menu.addItem(sessionItem)
                
                // Add submenu with details
                let submenu = NSMenu()
                
                // Info items
                if let cpu = session.cachedCPU {
                    let cpuItem = NSMenuItem(title: "📊 CPU: \(String(format: "%.1f", cpu))%", 
                                           action: nil, keyEquivalent: "")
                    cpuItem.isEnabled = false
                    submenu.addItem(cpuItem)
                }
                
                if let mem = session.cachedMemory {
                    let memItem = NSMenuItem(title: "💾 Memory: \(String(format: "%.1f", mem)) MB", 
                                           action: nil, keyEquivalent: "")
                    memItem.isEnabled = false
                    submenu.addItem(memItem)
                }
                
                let durationItem = NSMenuItem(title: "⏱️ Duration: \(session.formattedDuration)", 
                                            action: nil, keyEquivalent: "")
                durationItem.isEnabled = false
                submenu.addItem(durationItem)
                
                let terminalItem = NSMenuItem(title: "🖥️ Terminal: \(session.terminal)", 
                                            action: nil, keyEquivalent: "")
                terminalItem.isEnabled = false
                submenu.addItem(terminalItem)
                
                let pathItem = NSMenuItem(title: "📁 \(session.workingDir)", 
                                        action: nil, keyEquivalent: "")
                pathItem.isEnabled = false
                pathItem.toolTip = session.workingDir
                submenu.addItem(pathItem)
                
                submenu.addItem(NSMenuItem.separator())
                
                // Actions
                let jumpItem = NSMenuItem(title: "🔍 Jump to Session", 
                                        action: #selector(jumpToSession(_:)), 
                                        keyEquivalent: "")
                jumpItem.representedObject = session
                submenu.addItem(jumpItem)
                
                let killItem = NSMenuItem(title: "🚮 Kill Session", 
                                        action: #selector(killSession(_:)), 
                                        keyEquivalent: "")
                killItem.representedObject = session
                submenu.addItem(killItem)
                
                let copyPathItem = NSMenuItem(title: "📋 Copy Path", 
                                            action: #selector(copyPath(_:)), 
                                            keyEquivalent: "")
                copyPathItem.representedObject = session
                submenu.addItem(copyPathItem)
                
                sessionItem.submenu = submenu
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // Actions
        let actionsItem = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        actionsItem.isEnabled = false
        menu.addItem(actionsItem)
        
        let cleanupItem = NSMenuItem(title: "🧹 Cleanup Dead Sessions", 
                                   action: #selector(cleanupSessions), 
                                   keyEquivalent: "")
        menu.addItem(cleanupItem)
        
        let launchItem = NSMenuItem(title: "🚀 Launch New Claude", 
                                  action: #selector(launchNewClaude), 
                                  keyEquivalent: "")
        menu.addItem(launchItem)
        
        let openSessionsItem = NSMenuItem(title: "📂 Open Sessions Folder", 
                                        action: #selector(openSessionsFolder), 
                                        keyEquivalent: "")
        menu.addItem(openSessionsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let refreshItem = NSMenuItem(title: "🔄 Refresh Now", 
                                   action: #selector(refresh), 
                                   keyEquivalent: "r")
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // About & Quit
        let aboutItem = NSMenuItem(title: "About Claude Navigator", 
                                 action: #selector(showAbout), 
                                 keyEquivalent: "")
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit", 
                                action: #selector(NSApplication.terminate(_:)), 
                                keyEquivalent: "q")
        menu.addItem(quitItem)
    }
    
    // MARK: - Actions
    
    @objc func jumpToSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? ClaudeSession else { return }
        
        Task {
            do {
                try await TerminalNavigator.jumpToSession(session: session)
            } catch {
                print("Error jumping to session: \(error)")
                // Fallback to script
                try? await TerminalNavigator.jumpUsingScript(pid: session.pid)
            }
        }
    }
    
    @objc func killSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? ClaudeSession else { return }
        
        Task {
            _ = try? await ShellExecutor.run("kill \(session.pid)")
            // Refresh after a short delay to allow process to terminate
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            refresh()
        }
    }
    
    @objc func copyPath(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? ClaudeSession else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.workingDir, forType: .string)
    }
    
    @objc func cleanupSessions() {
        Task {
            _ = await sessionMonitor.cleanupDeadSessions()
            refresh()
        }
    }
    
    @objc func launchNewClaude() {
        Task {
            _ = try? await ShellExecutor.run("open -a Terminal /opt/homebrew/bin/claude")
        }
    }
    
    @objc func openSessionsFolder() {
        NSWorkspace.shared.open(ClaudeSessionMonitor.sessionsDirectory)
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Claude Terminal Navigator"
        alert.informativeText = """
        Version 1.0
        
        Monitor and navigate Claude CLI sessions from the menu bar.
        
        Created with Claude 🤖
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "View on GitHub")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/GailenTech/claude-terminal-navigator") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}