import AppKit
import SwiftUI

final class DetachedWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = DetachedWindowPresenter()

    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: CGSize, @ViewBuilder content: () -> Content) {
        let anyView = AnyView(content())

        if let existing = self.windows[id] {
            existing.title = title
            existing.setContentSize(size)
            if let controller = existing.contentViewController as? NSHostingController<AnyView> {
                controller.rootView = anyView
            } else {
                existing.contentViewController = NSHostingController(rootView: anyView)
            }
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: anyView)
        let window = NSWindow(contentViewController: controller)
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(size)
        window.delegate = self

        self.windows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close(id: String) {
        guard let window = self.windows[id] else { return }
        window.close()
        self.windows.removeValue(forKey: id)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        self.windows.removeValue(forKey: id)
    }
}

