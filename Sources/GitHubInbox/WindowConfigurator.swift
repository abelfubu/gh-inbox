import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(Theme.background)
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            #if DEBUG
            if ProcessInfo.processInfo.environment["GH_INBOX_WINDOW_SMOKE"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let hidden = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].allSatisfy {
                        window.standardWindowButton($0)?.isHidden == true
                    }
                    precondition(hidden, "Traffic-light buttons are still visible")
                    precondition(window.styleMask.contains(.resizable), "Window must remain resizable")
                    print("native window smoke: PASS")
                    exit(0)
                }
            }
            #endif
        }
    }
}
