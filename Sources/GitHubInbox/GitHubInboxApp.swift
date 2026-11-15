import AppKit
import SwiftUI

@main
struct GitHubInboxApp: App {
    @StateObject private var store = InboxStore()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GH_INBOX_SELF_TEST"] == "1" || CommandLine.arguments.contains("--self-test") { SelfTests.run() }
        #endif
    }

    var body: some Scene {
        WindowGroup("GitHub Inbox") {
            ContentView(store: store)
                .background(WindowConfigurator())
                .ignoresSafeArea()
                .frame(minWidth: 72, idealWidth: 380, minHeight: 320, idealHeight: 800)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 380, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh") { store.performShortcut(.refresh) }
                    .keyboardShortcut(store.shortcuts.keyboardShortcut(for: .refresh, preferred: "cmd-r"))
                Button("Open Config") { store.performShortcut(.openConfig) }
                    .keyboardShortcut(store.shortcuts.keyboardShortcut(for: .openConfig, preferred: "cmd-shift-o"))
                Button("Close") { store.performShortcut(.closeWindow) }
                    .keyboardShortcut(store.shortcuts.keyboardShortcut(for: .closeWindow, preferred: "cmd-w"))
            }
            CommandGroup(after: .sidebar) {
                Button("Previous Tab") { store.performShortcut(.previousTab) }
                    .keyboardShortcut(store.shortcuts.keyboardShortcut(for: .previousTab, preferred: "cmd-["))
                Button("Next Tab") { store.performShortcut(.nextTab) }
                    .keyboardShortcut(store.shortcuts.keyboardShortcut(for: .nextTab, preferred: "cmd-]"))
            }
        }
    }
}
