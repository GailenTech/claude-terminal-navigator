//
//  ClaudeNavigatorApp.swift
//  ClaudeNavigator
//
//  Created by Claude Terminal Navigator
//

import SwiftUI
import QuartzCore
import ServiceManagement

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

class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var sessionMonitor: ClaudeSessionMonitor!
    var detailWindow: NSWindow?
    var detailScrollView: NSScrollView?
    
    // Cache for performance
    private var lastActiveCount = 0
    private var lastWaitingCount = 0
    private var lastAttentionCount = 0
    private var cachedSessions: [ClaudeSession] = []
    private var lastCacheUpdate: Date = Date()
    private var cacheUpdateTimer: Timer?
    
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
        
        if let button = statusItem.button {
            // Set initial icon
            button.title = "🤖"
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            print("✅ Button configured with emoji title: \(button.title)")
        } else {
            print("❌ Failed to create status button!")
        }
        
        // Start refresh timer (5 seconds like xbar)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.refresh()
        }
        
        // Initial refresh to populate cache
        print("🔄 Starting initial refresh...")
        refresh()
        
        print("✅ ClaudeNavigator fully initialized!")
    }
    
    @objc func statusItemClicked() {
        let event = NSApp.currentEvent
        
        // Check for Option key (NSEvent.ModifierFlags.option) - inverted behavior
        if event?.modifierFlags.contains(.option) == true {
            showMenu()
        } else {
            showDetailedView()
        }
    }
    
    func showMenu() {
        if let button = statusItem.button {
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        }
    }
    
    func showDetailedView() {
        // Toggle behavior: if window exists and is visible, close it
        if let window = detailWindow, window.isVisible {
            print("🔍 Closing detailed view...")
            window.close()
            detailWindow = nil
            detailScrollView = nil
            return
        }
        
        print("🔍 Showing detailed view...")
        
        // Show window immediately with cached sessions if available
        if !cachedSessions.isEmpty {
            print("🔍 Using cached sessions (count: \(cachedSessions.count))")
            createDetailedWindow(with: cachedSessions)
        } else {
            // Show loading state if no cache
            createDetailedWindow(with: [])
        }
        
        // Then load fresh sessions asynchronously and update if different
        Task {
            do {
                let sessions = try await sessionMonitor.getActiveSessions()
                await MainActor.run {
                    // Only update if sessions have changed
                    if !self.sessionsEqual(self.cachedSessions, sessions) {
                        print("🔍 Updating window with fresh sessions")
                        self.updateDetailedWindow(with: sessions)
                    }
                }
            } catch {
                print("Error getting sessions for detailed view: \(error)")
            }
        }
    }
    
    func updateDetailedWindow(with sessions: [ClaudeSession]) {
        guard let window = detailWindow, let scrollView = detailScrollView else { return }
        
        // Save current scroll position
        let savedScrollPosition = scrollView.contentView.visibleRect.origin
        
        // Update only the document view content without recreating the entire view hierarchy
        if let documentView = scrollView.documentView as? FlippedView {
            // Remove all existing session views
            documentView.subviews.forEach { $0.removeFromSuperview() }
            
            // Add updated session views
            var yPosition: CGFloat = 0
            let sessionHeight: CGFloat = 100
            let margin: CGFloat = 10
            
            // Sort sessions: attention first, then active first, then by time
            let sortedSessions = sessions.sorted { session1, session2 in
                // First priority: sessions needing attention
                if session1.needsAttention != session2.needsAttention {
                    return session1.needsAttention && !session2.needsAttention
                }
                // Second priority: active vs waiting
                if session1.isActive != session2.isActive {
                    return session1.isActive && !session2.isActive
                }
                // Within same state, sort by start time (newest first)
                return session1.startTime > session2.startTime
            }
            
            for session in sortedSessions {
                let sessionView = createSessionView(session: session)
                sessionView.translatesAutoresizingMaskIntoConstraints = false
                documentView.addSubview(sessionView)
                
                NSLayoutConstraint.activate([
                    sessionView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: yPosition),
                    sessionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: margin),
                    sessionView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -margin),
                    sessionView.heightAnchor.constraint(equalToConstant: sessionHeight)
                ])
                
                yPosition += sessionHeight + margin
            }
            
            // Update document view height by removing old constraints and adding new one
            documentView.constraints.forEach { constraint in
                if constraint.firstAttribute == .height {
                    documentView.removeConstraint(constraint)
                }
            }
            documentView.heightAnchor.constraint(equalToConstant: max(yPosition, 300)).isActive = true
            
            // Restore scroll position
            DispatchQueue.main.async {
                scrollView.contentView.scroll(to: savedScrollPosition)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
    
    func createDetailedWindow(with sessions: [ClaudeSession]) {
        // Close existing window if any
        if detailWindow != nil {
            detailWindow?.close()
            detailWindow = nil
        }
        
        // Create window
        let windowRect = NSRect(x: 0, y: 0, width: 600, height: 400)
        detailWindow = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        detailWindow?.title = "Claude Sessions - Detailed View"
        detailWindow?.center()
        detailWindow?.isReleasedWhenClosed = false
        
        // Make window stay on top
        detailWindow?.level = .floating
        detailWindow?.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Create content view
        let contentView = createDetailedContentView(with: sessions)
        detailWindow?.contentView = contentView
        
        // Show window and ensure it gets focus
        detailWindow?.makeKeyAndOrderFront(nil)
        detailWindow?.orderFrontRegardless()
        
        // Force the app to become active and window to get focus
        NSApp.activate(ignoringOtherApps: true)
        detailWindow?.makeKey()
        detailWindow?.makeMain()
        
        // Set first responder to content view for immediate interaction
        DispatchQueue.main.async {
            self.detailWindow?.makeFirstResponder(self.detailWindow?.contentView)
        }
    }
    
    func createDetailedContentView(with sessions: [ClaudeSession]) -> NSView {
        let contentView = NSView()
        
        // Create header label with instructions or loading state
        let isFromCache = !cachedSessions.isEmpty && sessionsEqual(sessions, cachedSessions)
        let cacheAge = Int(Date().timeIntervalSince(lastCacheUpdate))
        let headerText: String
        if sessions.isEmpty {
            headerText = "Loading sessions..."
        } else if isFromCache && cacheAge > 2 {
            // Only show cache age if it's meaningful (more than 2 seconds)
            headerText = "Click any session to jump to it (cached \(cacheAge)s ago)"
        } else {
            headerText = "Click any session to jump to it"
        }
        
        let headerLabel = NSTextField(labelWithString: headerText)
        headerLabel.font = NSFont.systemFont(ofSize: 14)
        headerLabel.textColor = NSColor.secondaryLabelColor
        headerLabel.alignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerLabel)
        
        // Create scroll view for sessions
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        
        // Store reference for scroll position preservation
        detailScrollView = scrollView
        
        // Create document view with flipped coordinate system
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        
        var yPosition: CGFloat = 0
        let sessionHeight: CGFloat = 100
        let margin: CGFloat = 10
        
        // If no sessions, show loading indicator
        if sessions.isEmpty {
            let progressIndicator = NSProgressIndicator()
            progressIndicator.style = .spinning
            progressIndicator.translatesAutoresizingMaskIntoConstraints = false
            documentView.addSubview(progressIndicator)
            progressIndicator.startAnimation(nil)
            
            NSLayoutConstraint.activate([
                progressIndicator.centerXAnchor.constraint(equalTo: documentView.centerXAnchor),
                progressIndicator.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 50)
            ])
            
            yPosition = 100 // Leave space for the indicator
        } else {
            // Sort sessions: attention first, then active first, then by time
            let sortedSessions = sessions.sorted { session1, session2 in
                // First priority: sessions needing attention
                if session1.needsAttention != session2.needsAttention {
                    return session1.needsAttention && !session2.needsAttention
                }
                // Second priority: active vs waiting
                if session1.isActive != session2.isActive {
                    return session1.isActive && !session2.isActive
                }
                // Within same state, sort by start time (newest first)
                return session1.startTime > session2.startTime
            }
            
            for session in sortedSessions {
                let sessionView = createSessionView(session: session)
                sessionView.translatesAutoresizingMaskIntoConstraints = false
                documentView.addSubview(sessionView)
                
                // Position session view
                NSLayoutConstraint.activate([
                    sessionView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: yPosition),
                    sessionView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: margin),
                    sessionView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -margin),
                    sessionView.heightAnchor.constraint(equalToConstant: sessionHeight)
                ])
                
                yPosition += sessionHeight + margin
            }
        }
        
        // Set document view size
        documentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 580).isActive = true
        documentView.heightAnchor.constraint(equalToConstant: max(yPosition, 300)).isActive = true
        
        // Set document view and configure scroll view
        scrollView.documentView = documentView
        scrollView.verticalScrollElasticity = .automatic
        scrollView.hasVerticalScroller = true
        
        // Layout constraints
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            headerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
        
        return contentView
    }
    
    func createSessionView(session: ClaudeSession) -> NSView {
        let sessionView = ClickableSessionView()
        
        // Background
        sessionView.wantsLayer = true
        sessionView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sessionView.layer?.cornerRadius = 8
        sessionView.layer?.borderWidth = 1
        sessionView.layer?.borderColor = NSColor.separatorColor.cgColor
        
        // Add shadow for depth
        sessionView.shadow = NSShadow()
        sessionView.layer?.shadowColor = NSColor.black.cgColor
        sessionView.layer?.shadowOpacity = 0.1
        sessionView.layer?.shadowOffset = CGSize(width: 0, height: 2)
        sessionView.layer?.shadowRadius = 4
        
        // Status indicator with consistent icons
        let iconText: String
        if session.needsAttention {
            iconText = "🚨"   // Emergency - consistent with menu bar badge
        } else if session.isActive {
            iconText = "🤖"    // Active robot
        } else {
            iconText = "💤"    // Sleeping
        }
        
        let statusIcon = NSTextField(labelWithString: iconText)
        statusIcon.font = NSFont.systemFont(ofSize: 14)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        sessionView.addSubview(statusIcon)
        
        // Add animations based on session state
        statusIcon.wantsLayer = true
        
        if session.needsAttention {
            // More urgent orange pulsing for attention needed
            let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
            colorAnimation.fromValue = NSColor.clear.cgColor
            colorAnimation.toValue = NSColor.systemOrange.withAlphaComponent(0.8).cgColor
            colorAnimation.duration = 1.0  // Faster pulse for attention
            colorAnimation.repeatCount = .infinity
            colorAnimation.autoreverses = true
            colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Add random delay to desynchronize animations
            let randomDelay = Double.random(in: 0...0.5)
            colorAnimation.beginTime = CACurrentMediaTime() + randomDelay
            
            statusIcon.layer?.add(colorAnimation, forKey: "attentionPulse")
        } else if session.isActive {
            // Create a breathing/pulsing effect with background color
            let colorAnimation = CABasicAnimation(keyPath: "backgroundColor")
            colorAnimation.fromValue = NSColor.clear.cgColor
            colorAnimation.toValue = NSColor.systemRed.withAlphaComponent(0.7).cgColor
            colorAnimation.duration = 1.5
            colorAnimation.repeatCount = .infinity
            colorAnimation.autoreverses = true
            colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            // Add random delay to desynchronize animations
            let randomDelay = Double.random(in: 0...1.0)
            colorAnimation.beginTime = CACurrentMediaTime() + randomDelay
            
            statusIcon.layer?.add(colorAnimation, forKey: "colorPulse")
        }
        
        // Session title
        let titleLabel = NSTextField(labelWithString: session.dirName)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionView.addSubview(titleLabel)
        
        // PID and CPU info
        let cpuText = String(format: "PID: %@ | CPU: %.1f%% | Memory: %.1f MB", 
                           session.pid, 
                           session.cachedCPU ?? 0.0, 
                           session.cachedMemory ?? 0.0)
        let cpuLabel = NSTextField(labelWithString: cpuText)
        cpuLabel.font = NSFont.systemFont(ofSize: 11)
        cpuLabel.textColor = NSColor.secondaryLabelColor
        cpuLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionView.addSubview(cpuLabel)
        
        // Git information
        let gitText = formatGitInfo(branch: session.gitBranch, status: session.gitStatus)
        let gitLabel = NSTextField(labelWithString: gitText)
        gitLabel.font = NSFont.systemFont(ofSize: 11)
        gitLabel.textColor = NSColor.secondaryLabelColor
        gitLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionView.addSubview(gitLabel)
        
        // Duration
        let durationText = "Duration: \(session.formattedDuration)"
        let durationLabel = NSTextField(labelWithString: durationText)
        durationLabel.font = NSFont.systemFont(ofSize: 11)
        durationLabel.textColor = NSColor.secondaryLabelColor
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionView.addSubview(durationLabel)
        
        // Working directory
        let pathLabel = NSTextField(labelWithString: session.workingDir)
        pathLabel.font = NSFont.systemFont(ofSize: 10)
        pathLabel.textColor = NSColor.tertiaryLabelColor
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        sessionView.addSubview(pathLabel)
        
        // Store session PID in view for gesture recognition
        sessionView.identifier = NSUserInterfaceItemIdentifier(session.pid)
        
        // Add single-click gesture recognizer
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(sessionClicked(_:)))
        clickGesture.numberOfClicksRequired = 1
        sessionView.addGestureRecognizer(clickGesture)
        
        // Layout constraints for main content
        NSLayoutConstraint.activate([
            statusIcon.topAnchor.constraint(equalTo: sessionView.topAnchor, constant: 8),
            statusIcon.leadingAnchor.constraint(equalTo: sessionView.leadingAnchor, constant: 8),
            
            titleLabel.topAnchor.constraint(equalTo: sessionView.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionView.trailingAnchor, constant: -8),
            
            cpuLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            cpuLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            cpuLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionView.trailingAnchor, constant: -8),
            
            gitLabel.topAnchor.constraint(equalTo: cpuLabel.bottomAnchor, constant: 2),
            gitLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            gitLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionView.trailingAnchor, constant: -8),
            
            durationLabel.topAnchor.constraint(equalTo: gitLabel.bottomAnchor, constant: 2),
            durationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            durationLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionView.trailingAnchor, constant: -8),
            
            pathLabel.topAnchor.constraint(equalTo: durationLabel.bottomAnchor, constant: 2),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionView.trailingAnchor, constant: -8),
            pathLabel.bottomAnchor.constraint(lessThanOrEqualTo: sessionView.bottomAnchor, constant: -8)
        ])
        
        return sessionView
    }
    
    func formatGitInfo(branch: String?, status: String?) -> String {
        var parts: [String] = []
        
        if let branch = branch {
            parts.append("🌿 \(branch)")
        }
        
        if let status = status {
            let statusIcon = status == "clean" ? "✅" : "📝"
            parts.append("\(statusIcon) \(status)")
        }
        
        return parts.isEmpty ? "📂 No Git repository" : parts.joined(separator: " | ")
    }
    
    
    @objc func sessionClicked(_ gesture: NSClickGestureRecognizer) {
        guard let sessionView = gesture.view,
              let pidString = sessionView.identifier?.rawValue else { return }
        
        // Clear attention flag when user interacts with session
        sessionMonitor.clearAttentionFlag(for: pidString)
        
        // Force immediate UI refresh to clear attention badge
        refresh()
        
        Task {
            do {
                let sessions = try await sessionMonitor.getActiveSessions()
                if let session = sessions.first(where: { $0.pid == pidString }) {
                    try await TerminalNavigator.jumpToSession(session: session)
                    
                    // Fade out window after successful jump
                    await MainActor.run {
                        NSAnimationContext.runAnimationGroup({ context in
                            context.duration = 0.5
                            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                            self.detailWindow?.animator().alphaValue = 0.0
                        }, completionHandler: {
                            self.detailWindow?.close()
                            self.detailWindow = nil
                            self.detailScrollView = nil
                        })
                    }
                }
            } catch {
                print("Error jumping to session: \(error)")
                // Fallback to script
                try? await TerminalNavigator.jumpUsingScript(pid: pidString)
                
                // Still fade out on fallback
                await MainActor.run {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.5
                        self.detailWindow?.animator().alphaValue = 0.0
                    }, completionHandler: {
                        self.detailWindow?.close()
                    })
                }
            }
        }
    }
    
    func updateIcon(activeCount: Int, waitingCount: Int, attentionCount: Int = 0) {
        guard let button = statusItem.button else { return }
        
        // Track attention count changes too
        let attentionCountChanged = attentionCount != lastAttentionCount
        lastAttentionCount = attentionCount
        
        // Only update if counts changed
        if activeCount == lastActiveCount && waitingCount == lastWaitingCount && !attentionCountChanged {
            return
        }
        
        lastActiveCount = activeCount
        lastWaitingCount = waitingCount
        
        let totalCount = activeCount + waitingCount
        
        // Debug attention count with session details
        if attentionCount > 0 {
            let attentionSessions = cachedSessions.filter { $0.needsAttention }
            let pids = attentionSessions.map { $0.pid }.joined(separator: ", ")
            print("🔔 Attention badge: \(attentionCount) sessions need attention (PIDs: \(pids))")
        } else if attentionCountChanged {
            print("✅ Attention badge cleared - no sessions need attention")
        }
        
        DispatchQueue.main.async {
            // Ultra-compact format to avoid camera notch issues
            let attentionEmoji = attentionCount > 0 ? "🚨" : ""
            
            if activeCount > 0 {
                button.title = "\(attentionEmoji)🤖\(activeCount)/\(totalCount)"
                let attentionInfo = attentionCount > 0 ? ", \(attentionCount) need attention" : ""
                button.toolTip = "\(activeCount) active, \(waitingCount) waiting\(attentionInfo)"
            } else if waitingCount > 0 {
                button.title = "\(attentionEmoji)🤖0/\(totalCount)"
                let attentionInfo = attentionCount > 0 ? ", \(attentionCount) need attention" : ""
                button.toolTip = "All \(waitingCount) sessions waiting\(attentionInfo)"
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
    
    // Helper to compare sessions for changes
    func sessionsEqual(_ sessions1: [ClaudeSession], _ sessions2: [ClaudeSession]) -> Bool {
        if sessions1.count != sessions2.count {
            return false
        }
        
        // Create dictionaries for efficient comparison
        let dict1 = Dictionary(uniqueKeysWithValues: sessions1.map { ($0.pid, $0) })
        let dict2 = Dictionary(uniqueKeysWithValues: sessions2.map { ($0.pid, $0) })
        
        // Check if same PIDs
        if Set(dict1.keys) != Set(dict2.keys) {
            return false
        }
        
        // Check if session properties changed
        for pid in dict1.keys {
            guard let s1 = dict1[pid], let s2 = dict2[pid] else { return false }
            
            // Compare relevant properties
            if s1.isActive != s2.isActive ||
               s1.workingDir != s2.workingDir ||
               s1.cachedCPU != s2.cachedCPU ||
               s1.cachedMemory != s2.cachedMemory ||
               s1.gitBranch != s2.gitBranch ||
               s1.gitStatus != s2.gitStatus {
                return false
            }
        }
        
        return true
    }
    
    @objc func refresh() {
        Task {
            do {
                let sessions = try await sessionMonitor.getActiveSessions()
                await MainActor.run {
                    // Update cache
                    self.cachedSessions = sessions
                    self.lastCacheUpdate = Date()
                    
                    // Update menu
                    self.updateMenu(with: sessions)
                    
                    // Update detailed window if open
                    if self.detailWindow?.isVisible == true {
                        print("🔄 Auto-refreshing detailed view with new data")
                        self.updateDetailedWindow(with: sessions)
                    }
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
        let attentionSessions = sessions.filter { $0.needsAttention }
        
        // Update icon
        updateIcon(activeCount: activeSessions.count, waitingCount: waitingSessions.count, attentionCount: attentionSessions.count)
        
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
            // Sort sessions: attention first, then active first, then by CPU usage
            let sortedSessions = sessions.sorted { s1, s2 in
                // First priority: sessions needing attention
                if s1.needsAttention != s2.needsAttention {
                    return s1.needsAttention && !s2.needsAttention
                }
                // Second priority: active vs waiting
                if s1.isActive != s2.isActive {
                    return s1.isActive
                }
                // Within same state, sort by CPU usage
                return (s1.cachedCPU ?? 0) > (s2.cachedCPU ?? 0)
            }
            
            for session in sortedSessions {
                let icon: String
                if session.needsAttention {
                    icon = "🚨"   // Emergency - consistent with menu bar badge
                } else if session.isActive {
                    icon = "🤖"    // Active robot
                } else {
                    icon = "💤"    // Sleeping
                }
                
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
        
        // Settings
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)
        
        let launchAtStartupItem = NSMenuItem(title: "Launch at Startup", 
                                           action: #selector(toggleLaunchAtStartup), 
                                           keyEquivalent: "")
        launchAtStartupItem.state = LaunchAtStartup.isEnabled ? .on : .off
        menu.addItem(launchAtStartupItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Analytics
        let analyticsItem = NSMenuItem(title: "📊 Session Analytics", 
                                     action: #selector(showAnalytics), 
                                     keyEquivalent: "")
        menu.addItem(analyticsItem)
        
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
        
        // Clear attention flag when user interacts with session
        sessionMonitor.clearAttentionFlag(for: session.pid)
        
        // Force immediate UI refresh to clear attention badge
        refresh()
        
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
    
    @objc func toggleLaunchAtStartup() {
        LaunchAtStartup.toggle()
        refresh() // Refresh menu to update checkmark
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Claude Terminal Navigator"
        
        // Get version from Info.plist
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        
        alert.informativeText = """
        Version \(version) (Build \(build))
        
        Monitor and navigate Claude CLI sessions from the menu bar.
        
        Features:
        • Real-time session tracking
        • CPU & memory monitoring
        • Session analytics & history
        • Git branch awareness
        • One-click navigation
        
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
    
    @objc func showAnalytics() {
        // Show analytics with period selector
        showAnalyticsWithPeriod(days: 7, periodName: "Last 7 Days")
    }
    
    func showAnalyticsWithPeriod(days: Int?, periodName: String) {
        // Debug database contents
        SessionDatabase.shared.debugDatabaseContents()
        
        // Get recent sessions from database
        let recentSessions = SessionDatabase.shared.getRecentSessions(limit: 50)
        let stats = SessionDatabase.shared.getSessionStats(days: days)
        
        // Count active vs completed sessions
        let activeSessions = recentSessions.filter { $0.endTime == nil }
        let completedSessions = recentSessions.filter { $0.endTime != nil }
        
        let alert = NSAlert()
        alert.messageText = "📊 Session Analytics"
        alert.informativeText = """
        Database Status: \(recentSessions.isEmpty ? "No data yet - wait ~1 minute" : "Active ✅")
        Total DB Sessions: \(recentSessions.count)
        
        🟢 Active Sessions: \(activeSessions.count)
        \(activeSessions.prefix(3).map { session in
            let duration = Int(Date().timeIntervalSince(session.startTime) / 60)
            return "  • \(session.projectPath.split(separator: "/").last ?? "Unknown") - \(duration)m"
        }.joined(separator: "\n"))
        
        📈 \(periodName) Summary:
        • Total Sessions: \(stats.totalSessions)
        • Total Time: \(stats.formattedDuration)
        • Average CPU: \(String(format: "%.1f", stats.avgCPU))%
        • Average Memory: \(String(format: "%.1f", stats.avgMemory)) MB
        
        📋 Recent Completed: \(completedSessions.count)
        \(completedSessions.prefix(3).map { session in
            "  • \(session.projectPath.split(separator: "/").last ?? "Unknown") - \(Int(session.duration / 60))m"
        }.joined(separator: "\n"))
        
        💡 Tip: Metrics update every ~50 seconds for active sessions.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Change Period")
        alert.addButton(withTitle: "Force Save Snapshot")
        alert.addButton(withTitle: "Export Data")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            // Change Period button clicked
            showPeriodSelector()
        } else if response == .alertThirdButtonReturn {
            // Force Save Snapshot button clicked
            forceSaveCurrentSnapshots()
        } else if response == NSApplication.ModalResponse(rawValue: 1003) {
            // Export Data button clicked (4th button)
            exportAnalyticsData()
        }
    }
    
    func forceSaveCurrentSnapshots() {
        Task {
            do {
                // Get all active sessions
                let sessions = try await sessionMonitor.getActiveSessions()
                
                // Force save each session
                var savedCount = 0
                for session in sessions {
                    // Create a test session history record directly
                    let testHistory = SessionHistory(
                        id: UUID(),
                        startTime: Date(),
                        endTime: nil,  // Active session
                        projectPath: session.workingDir,
                        gitBranch: session.gitBranch,
                        gitRepo: extractRepoName(from: session.workingDir),
                        peakCPU: session.cachedCPU ?? 0,
                        avgCPU: session.cachedCPU ?? 0,
                        peakMemory: session.cachedMemory ?? 0,
                        avgMemory: session.cachedMemory ?? 0,
                        messageCount: 1,
                        filesModified: 0,
                        linesAdded: 0,
                        linesRemoved: 0,
                        errorsCount: 0,
                        toolUsage: ["Manual Save": 1]
                    )
                    
                    // Save directly to database
                    SessionDatabase.shared.saveSession(testHistory)
                    savedCount += 1
                    print("📊 Force saved session for PID: \(session.pid)")
                }
                
                let finalSavedCount = savedCount
                await MainActor.run {
                    // Show success message
                    let successAlert = NSAlert()
                    successAlert.messageText = "Force Save Complete"
                    successAlert.informativeText = """
                    Saved \(finalSavedCount) active sessions to database.
                    
                    Database path: ~/Library/Application Support/ClaudeNavigator/sessions.db
                    
                    Try viewing analytics again to see if data appears.
                    """
                    successAlert.alertStyle = .informational
                    successAlert.runModal()
                    
                    // Refresh analytics view
                    self.showAnalytics()
                }
            } catch {
                await MainActor.run {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "Force Save Failed"
                    errorAlert.informativeText = "Error: \(error.localizedDescription)"
                    errorAlert.alertStyle = .critical
                    errorAlert.runModal()
                }
            }
        }
    }
    
    func extractRepoName(from path: String) -> String? {
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
    
    func showPeriodSelector() {
        let alert = NSAlert()
        alert.messageText = "Select Time Period"
        alert.informativeText = "Choose the time period for analytics:"
        alert.alertStyle = .informational
        
        alert.addButton(withTitle: "Last 24 Hours")
        alert.addButton(withTitle: "Last 7 Days")
        alert.addButton(withTitle: "Last 30 Days")
        alert.addButton(withTitle: "All Time")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            showAnalyticsWithPeriod(days: 1, periodName: "Last 24 Hours")
        case .alertSecondButtonReturn:
            showAnalyticsWithPeriod(days: 7, periodName: "Last 7 Days")
        case .alertThirdButtonReturn:
            showAnalyticsWithPeriod(days: 30, periodName: "Last 30 Days")
        case NSApplication.ModalResponse(rawValue: 1003):
            showAnalyticsWithPeriod(days: nil, periodName: "All Time")
        default:
            // Cancel - do nothing
            break
        }
    }
    
    func exportAnalyticsData() {
        // TODO: Export to CSV/JSON
        let alert = NSAlert()
        alert.messageText = "Export Coming Soon"
        alert.informativeText = "This feature will export session data to CSV format."
        alert.runModal()
    }
}

// MARK: - Custom Clickable Session View

class ClickableSessionView: NSView {
    private var isPressed = false
    private var trackingArea: NSTrackingArea?
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.push()
        animateHover(isHovering: true)
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        animateHover(isHovering: false)
        if isPressed {
            isPressed = false
            animatePress(isPressed: false)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        animatePress(isPressed: true)
    }
    
    override func mouseUp(with event: NSEvent) {
        if isPressed {
            isPressed = false
            animatePress(isPressed: false)
        }
    }
    
    private func animateHover(isHovering: Bool) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            if isHovering {
                self.animator().layer?.backgroundColor = NSColor.controlBackgroundColor.blended(withFraction: 0.05, of: NSColor.controlAccentColor)?.cgColor
                self.animator().layer?.shadowOpacity = 0.15
            } else {
                self.animator().layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                self.animator().layer?.shadowOpacity = 0.1
            }
        })
    }
    
    private func animatePress(isPressed: Bool) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            if isPressed {
                // Scale down slightly and reduce shadow
                let transform = CATransform3DMakeScale(0.98, 0.98, 1.0)
                self.animator().layer?.transform = transform
                self.animator().layer?.shadowOpacity = 0.05
                self.animator().layer?.shadowOffset = CGSize(width: 0, height: 1)
            } else {
                // Return to normal
                self.animator().layer?.transform = CATransform3DIdentity
                self.animator().layer?.shadowOpacity = 0.1
                self.animator().layer?.shadowOffset = CGSize(width: 0, height: 2)
            }
        })
    }
}

// MARK: - Launch at Startup Helper

class LaunchAtStartup {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            // Use the modern API for macOS 13+
            return SMAppService.mainApp.status == .enabled
        } else {
            // For older macOS versions, check using legacy method
            let jobDicts = SMCopyAllJobDictionaries(kSMDomainUserLaunchd).takeRetainedValue() as? [[String: Any]] ?? []
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            return jobDicts.contains { dict in
                if let label = dict["Label"] as? String {
                    return label == bundleId
                }
                return false
            }
        }
    }
    
    static func toggle() {
        if #available(macOS 13.0, *) {
            // Use the modern API for macOS 13+
            do {
                if isEnabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("Failed to toggle launch at startup: \(error)")
            }
        } else {
            // For older macOS versions, use AppleScript
            let script = isEnabled ? disableScript : enableScript
            
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if let error = error {
                    print("Failed to toggle launch at startup: \(error)")
                }
            }
        }
    }
    
    private static var enableScript: String {
        let appPath = Bundle.main.bundlePath
        return """
        tell application "System Events"
            make new login item at end with properties {name:"ClaudeNavigator", path:"\(appPath)", hidden:false}
        end tell
        """
    }
    
    private static var disableScript: String {
        return """
        tell application "System Events"
            delete login item "ClaudeNavigator"
        end tell
        """
    }
}