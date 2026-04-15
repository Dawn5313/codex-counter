import Foundation
import XCTest

@MainActor
final class MenuHostBootstrapServiceTests: CodexBarTestCase {
    func testHelperNeedsRefreshWhenSourceSignatureChangesWithoutVersionBump() throws {
        let sourceURL = try self.makeFakeApp(
            named: "Source.app",
            bundleIdentifier: "com.dawn5313.ccodexr",
            executableName: "ccodexr",
            bundleVersion: "8",
            executableContents: "source-v1"
        )
        let helperURL = try self.makeFakeApp(
            named: "Helper.app",
            bundleIdentifier: MenuHostBootstrapService.helperBundleIdentifier,
            executableName: "ccodexr",
            bundleVersion: "8",
            executableContents: "source-v1",
            extraInfo: [
                MenuHostBootstrapService.helperSourceVersionKey: "8",
                MenuHostBootstrapService.helperSourceSignatureKey: try XCTUnwrap(
                    MenuHostBootstrapService.helperSourceSignature(for: sourceURL)
                ),
            ]
        )

        try self.writeExecutable(
            in: sourceURL,
            executableName: "ccodexr",
            contents: "source-v2-without-version-change"
        )

        XCTAssertTrue(
            MenuHostBootstrapService.helperNeedsRefresh(
                at: helperURL,
                sourceURL: sourceURL
            )
        )
    }

    func testHelperNeedsRefreshFallsBackToBundleVersionWhenSignatureMissing() throws {
        let sourceURL = try self.makeFakeApp(
            named: "Source.app",
            bundleIdentifier: "com.dawn5313.ccodexr",
            executableName: "ccodexr",
            bundleVersion: "9",
            executableContents: "source-v1"
        )
        let helperURL = try self.makeFakeApp(
            named: "Helper.app",
            bundleIdentifier: MenuHostBootstrapService.helperBundleIdentifier,
            executableName: "ccodexr",
            bundleVersion: "8",
            executableContents: "source-v1",
            extraInfo: [
                MenuHostBootstrapService.helperSourceVersionKey: "8",
            ]
        )

        XCTAssertTrue(
            MenuHostBootstrapService.helperNeedsRefresh(
                at: helperURL,
                sourceURL: sourceURL
            )
        )
    }

    func testHelperNeedsRefreshWhenStoredSignatureIsMissingEvenIfVersionMatches() throws {
        let sourceURL = try self.makeFakeApp(
            named: "Source.app",
            bundleIdentifier: "com.dawn5313.ccodexr",
            executableName: "ccodexr",
            bundleVersion: "8",
            executableContents: "source-v1"
        )
        let helperURL = try self.makeFakeApp(
            named: "Helper.app",
            bundleIdentifier: MenuHostBootstrapService.helperBundleIdentifier,
            executableName: "ccodexr",
            bundleVersion: "8",
            executableContents: "source-v1",
            extraInfo: [
                MenuHostBootstrapService.helperSourceVersionKey: "8",
            ]
        )

        XCTAssertTrue(
            MenuHostBootstrapService.helperNeedsRefresh(
                at: helperURL,
                sourceURL: sourceURL
            )
        )
    }

    private func makeFakeApp(
        named appName: String,
        bundleIdentifier: String,
        executableName: String,
        bundleVersion: String,
        executableContents: String,
        extraInfo: [String: Any] = [:]
    ) throws -> URL {
        let appURL = CodexPaths.realHome.appendingPathComponent(appName, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        try self.writeExecutable(
            in: appURL,
            executableName: executableName,
            contents: executableContents
        )

        var info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleExecutable": executableName,
            "CFBundleName": "ccodexr",
            "CFBundleDisplayName": "ccodexr",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": bundleVersion,
            "CFBundleShortVersionString": "1.1.8",
        ]
        for (key, value) in extraInfo {
            info[key] = value
        }

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try plistData.write(
            to: contentsURL.appendingPathComponent("Info.plist"),
            options: .atomic
        )

        return appURL
    }

    private func writeExecutable(
        in appURL: URL,
        executableName: String,
        contents: String
    ) throws {
        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        try Data(contents.utf8).write(to: executableURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )
    }
}
