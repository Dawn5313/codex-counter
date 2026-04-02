import AppKit
import SwiftUI

private final class HoverPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

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

    func showHoverPanel<Content: View>(id: String, size: CGSize, origin: CGPoint, @ViewBuilder content: () -> Content) {
        let anyView = AnyView(content())

        if let existing = self.windows[id] {
            if existing.frame.size != size {
                existing.setContentSize(size)
            }
            if existing.frame.origin != origin {
                existing.setFrameOrigin(origin)
            }
            if let controller = existing.contentViewController as? NSHostingController<AnyView> {
                controller.rootView = anyView
            } else {
                existing.contentViewController = NSHostingController(rootView: anyView)
            }
            existing.orderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: anyView)
        let window = HoverPanelWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.contentViewController = controller
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.delegate = self

        self.windows[id] = window
        window.orderFront(nil)
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
