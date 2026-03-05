//
//  RefinerApp.swift
//  Refiner
//

import SwiftUI
import Carbon.HIToolbox

// MARK: - Entry Point

@main
struct RefinerApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no dock icon
        app.run()
    }
}

// MARK: - Four-Char Code Helper

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = result << 8 + OSType(char)
    }
    return result
}

// MARK: - HotKey UserDefaults

enum HotKeyDefaults {
    static let keyCodeKey = "globalHotKeyCode"
    static let modifiersKey = "globalHotKeyModifiers"
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_R)
    static let defaultModifiers: UInt32 = UInt32(cmdKey | optionKey)
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var settingsWindow: NSWindow?
    private var eventHandlerInstalled = false
    private var isHidingPanel = false
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        setupMainMenu()
        setupStatusItem()

        // Create the floating panel
        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel?.titlebarAppearsTransparent = true
        panel?.titleVisibility = .hidden
        panel?.level = .floating
        panel?.isMovableByWindowBackground = true
        panel?.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel?.animationBehavior = .utilityWindow
        panel?.isOpaque = false
        panel?.backgroundColor = .clear
        panel?.minSize = NSSize(width: 400, height: 300)
        panel?.standardWindowButton(.closeButton)?.isHidden = true
        panel?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel?.standardWindowButton(.zoomButton)?.isHidden = true

        // Host the SwiftUI ContentView
        let hostingView = NSHostingView(rootView: ContentView())
        panel?.contentView = hostingView

        // Wire up resignKey callback
        panel?.onResignKey = { [weak self] in
            self?.hidePanel()
        }

        // Register global hotkey: Cmd+Opt+R
        registerHotKey()

        // Show the panel on launch
        centerOnActiveScreen()
        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 1
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (required, even if empty)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Refiner", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Refiner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu — enables Cmd+V, Cmd+C, Cmd+X, Cmd+A
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Refiner")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Refiner", action: #selector(statusItemTogglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Refiner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func statusItemTogglePanel() {
        togglePanel()
    }

    // MARK: - Settings

    @objc func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Settings"
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(onShortcutChanged: { [weak self] in
            self?.registerHotKey()
        }))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Hotkey Registration

    private func installHotKeyEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.togglePanel()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            nil
        )
    }

    func registerHotKey() {
        installHotKeyEventHandler()

        // Unregister previous hotkey if any
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }

        let kc = UserDefaults.standard.object(forKey: HotKeyDefaults.keyCodeKey) as? UInt32 ?? HotKeyDefaults.defaultKeyCode
        let mods = UserDefaults.standard.object(forKey: HotKeyDefaults.modifiersKey) as? UInt32 ?? HotKeyDefaults.defaultModifiers

        let hotKeyID = EventHotKeyID(signature: fourCharCode("RFNR"), id: 1)
        RegisterEventHotKey(
            kc,
            mods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: - Panel Toggle

    func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        centerOnActiveScreen()
        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 1
        }
        NSApp.activate(ignoringOtherApps: true)
        // Restore first responder to the content view so TextEditor receives keystrokes
        if let contentView = panel?.contentView {
            panel?.makeFirstResponder(contentView)
        }
    }

    func hidePanel() {
        guard !isHidingPanel else { return }
        isHidingPanel = true
        // Save panel frame (position + size) before hiding
        panel?.saveFrame(usingName: "RefinerPanel")
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.isHidingPanel = false
        })
    }

    // MARK: - Positioning

    private func centerOnActiveScreen() {
        // Restore saved frame if available
        if panel?.setFrameUsingName("RefinerPanel") == true {
            return
        }

        // First launch: center with default size
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 800
        let panelHeight: CGFloat = 500
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.origin.y + screenFrame.height * 0.7 - panelHeight / 2
        panel?.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }
}

// MARK: - Floating Panel

class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onResignKey?()
        } else {
            super.keyDown(with: event)
        }
    }
}
