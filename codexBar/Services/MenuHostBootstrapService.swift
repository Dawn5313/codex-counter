import AppKit
import Foundation

enum CodexBarInterprocess {
    static let reloadStateNotification = Notification.Name("com.dawn5313.ccodexr.reload-state")
    static let terminatePrimaryNotification = Notification.Name("com.dawn5313.ccodexr.terminate-primary")

    static func postReloadState() {
        DistributedNotificationCenter.default().post(
            name: self.reloadStateNotification,
            object: nil
        )
    }

    static func postTerminatePrimary() {
        DistributedNotificationCenter.default().post(
            name: self.terminatePrimaryNotification,
            object: nil
        )
    }
}

@MainActor
final class MenuHostBootstrapService {
    static let shared = MenuHostBootstrapService()

    nonisolated static let helperBundleIdentifier = "com.dawn5313.ccodexr.menuhost"
    nonisolated static let helperMarkerInfoKey = "CodexBarMenuHost"
    nonisolated static let helperSourceVersionKey = "CodexBarMenuHostSourceVersion"
    nonisolated static let helperSourceSignatureKey = "CodexBarMenuHostSourceSignature"

    static var isMenuHostProcess: Bool {
        if Bundle.main.object(forInfoDictionaryKey: self.helperMarkerInfoKey) as? Bool == true {
            return true
        }
        return Bundle.main.bundleIdentifier == self.helperBundleIdentifier
    }

    private let fileManager = FileManager.default

    private init() {}

    func ensureMenuHostRunning() {
        guard Self.isMenuHostProcess == false else { return }

        do {
            let helperURL = try self.prepareMenuHostApp()
            if self.helperIsRunning() == false {
                try self.launchHelper(at: helperURL)
            }
        } catch {
            NSLog("ccodexr menu host bootstrap failed: %@", error.localizedDescription)
        }
    }

    private func prepareMenuHostApp() throws -> URL {
        try CodexPaths.ensureDirectories()

        let helperURL = CodexPaths.menuHostAppURL
        let sourceURL = Bundle.main.bundleURL

        if Self.helperNeedsRefresh(
            at: helperURL,
            sourceURL: sourceURL,
            fileManager: self.fileManager
        ) {
            try self.replaceHelperBundle(at: helperURL, from: sourceURL)
        }

        return helperURL
    }

    nonisolated static func helperNeedsRefresh(
        at helperURL: URL,
        sourceURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: helperURL.path) else { return true }
        guard let helperBundle = Bundle(url: helperURL) else {
            return true
        }

        if let sourceSignature = self.helperSourceSignature(
            for: sourceURL,
            fileManager: fileManager
        ) {
            guard let storedSourceSignature = helperBundle.object(
                forInfoDictionaryKey: Self.helperSourceSignatureKey
            ) as? String else {
                return true
            }
            return storedSourceSignature != sourceSignature
        }

        guard let sourceBundle = Bundle(url: sourceURL),
              let sourceVersion = sourceBundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
              ) as? String,
              let storedSourceVersion = helperBundle.object(
                forInfoDictionaryKey: Self.helperSourceVersionKey
              ) as? String else {
            return true
        }

        return storedSourceVersion != sourceVersion
    }

    nonisolated static func helperSourceSignature(
        for bundleURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard let bundle = Bundle(url: bundleURL),
              let executableURL = bundle.executableURL else {
            return nil
        }

        let infoPlistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")

        guard let executableSignature = self.fileRefreshSignature(
            at: executableURL,
            fileManager: fileManager
        ),
        let infoPlistSignature = self.fileRefreshSignature(
            at: infoPlistURL,
            fileManager: fileManager
        ) else {
            return nil
        }

        let bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return [
            bundleVersion,
            executableSignature,
            infoPlistSignature,
        ].joined(separator: "|")
    }

    private nonisolated static func fileRefreshSignature(
        at fileURL: URL,
        fileManager: FileManager
    ) -> String? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return "\(size.int64Value):\(modificationDate.timeIntervalSince1970)"
    }

    private func replaceHelperBundle(at helperURL: URL, from sourceURL: URL) throws {
        if self.helperIsRunning(),
           let runningHelper = NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.helperBundleIdentifier
           ).first {
            runningHelper.terminate()
            self.waitForHelperToExit(processIdentifier: runningHelper.processIdentifier, timeout: 2)
            if self.helperIsRunning() {
                _ = runningHelper.forceTerminate()
                self.waitForHelperToExit(processIdentifier: runningHelper.processIdentifier, timeout: 2)
            }
        }

        if self.fileManager.fileExists(atPath: helperURL.path) {
            try self.fileManager.removeItem(at: helperURL)
        }

        try self.fileManager.copyItem(at: sourceURL, to: helperURL)
        try self.patchHelperInfoPlist(at: helperURL.appendingPathComponent("Contents/Info.plist"))
    }

    private func patchHelperInfoPlist(at plistURL: URL) throws {
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw NSError(domain: "ccodexr.helper", code: 1)
        }

        plist["CFBundleIdentifier"] = Self.helperBundleIdentifier
        plist["CFBundleDisplayName"] = "ccodexr"
        plist["CFBundleName"] = "ccodexr"
        plist[Self.helperMarkerInfoKey] = true
        plist[Self.helperSourceVersionKey] = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        )
        plist[Self.helperSourceSignatureKey] = Self.helperSourceSignature(
            for: Bundle.main.bundleURL,
            fileManager: self.fileManager
        )
        plist.removeValue(forKey: "CFBundleURLTypes")

        let patched = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try patched.write(to: plistURL, options: .atomic)
    }

    private func waitForHelperToExit(processIdentifier: pid_t, timeout: TimeInterval) {
        guard processIdentifier > 0 else { return }
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while Date() < deadline {
            let isStillRunning = NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.helperBundleIdentifier
            ).contains(where: { $0.processIdentifier == processIdentifier })
            guard isStillRunning else { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func helperIsRunning() -> Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.helperBundleIdentifier
        ).isEmpty == false
    }

    private func launchHelper(at helperURL: URL) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { _, error in
            if let error {
                NSLog("ccodexr failed to launch menu host: %@", error.localizedDescription)
            }
        }
    }
}
