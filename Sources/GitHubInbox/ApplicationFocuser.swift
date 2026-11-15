import AppKit
import Foundation

enum ApplicationFocuser {
    static func focus(applicationNamed name: String) {
        DispatchQueue.main.async {
            let app = NSWorkspace.shared.runningApplications.first {
                    $0.bundleURL?.deletingPathExtension().lastPathComponent == name
                }
            app?.activate(options: [.activateAllWindows])
        }
    }

    static func focus(pid: pid_t) {
        DispatchQueue.main.async {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        }
    }
}
