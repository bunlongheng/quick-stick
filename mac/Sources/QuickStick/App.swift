import AppKit
import SwiftUI

@main
struct QuickStickApp: App {
    @StateObject private var state = AppState()
    @State private var opened = false

    var body: some Scene {
        WindowGroup {
            GridView()
                .environmentObject(state)
                .onAppear {
                    state.load()
                    // The web app opens with nothing focused, and a cell that
                    // holds focus is a cell you cannot drag. Hand it back.
                    DispatchQueue.main.async {
                        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
                        window.makeFirstResponder(nil)
                        // The board wants the whole screen, not a 1100pt
                        // rectangle. Once per launch, and never if the window
                        // was already restored full screen.
                        if !opened, !window.styleMask.contains(.fullScreen) {
                            opened = true
                            window.toggleFullScreen(nil)
                        }
                    }
                }
                // Coming back to the app is the moment to find out what the web
                // app wrote while it had the keyboard.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await state.pull() }
                }
                // Full screen is the only state this board has. However it got
                // out - green button, View menu, the shortcut - it goes back.
                // The hop is deferred because AppKit is still mid-transition
                // when this fires and ignores a toggle sent inside it.
                .onReceive(NotificationCenter.default.publisher(
                    for: NSWindow.didExitFullScreenNotification)) { note in
                    guard let window = note.object as? NSWindow else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        window.toggleFullScreen(nil)
                    }
                }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .saveItem) {
                // Nothing to press, but the reflex deserves an answer.
                Button("Save Now") { NotificationCenter.default.post(name: .syncNow, object: nil) }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Done") { NotificationCenter.default.post(name: .markDone, object: nil) }
                    .keyboardShortcut("d", modifiers: .command)
                Button("Settings") { state.settingsOpen.toggle() }
                    .keyboardShortcut(",", modifiers: .command)
                Button("Refresh") { Task { await state.pull() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            // macOS moved full screen to Globe+F; Ctrl+Cmd+F is still the
            // reflex, and a shortcut only exists if a menu item carries it.
            CommandGroup(before: .toolbar) {
                Button("Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
                    .keyboardShortcut("f", modifiers: [.control, .command])
                Divider()
            }
        }
    }
}
