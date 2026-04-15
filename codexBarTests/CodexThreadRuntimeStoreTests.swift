import Foundation
import XCTest

final class CodexThreadRuntimeStoreTests: CodexBarTestCase {
    func testLoadRunningThreadsReadsCurrentSchemaFixtures() throws {
        let now = self.date("2026-04-05T12:00:00Z")
        let store = self.makeStore()
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-app",
                    source: "vscode",
                    cwd: "/repo/app",
                    title: "App thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
                .init(
                    id: "thread-cli",
                    source: "cli",
                    cwd: "/repo/cli",
                    title: "CLI thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
                .init(
                    id: "thread-subagent",
                    source: #"{"subagent":{"thread_spawn":{"parent_thread_id":"root","depth":1}}}"#,
                    cwd: "/repo/subagent",
                    title: "Subagent thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
                .init(
                    id: "thread-stale",
                    source: "cli",
                    cwd: "/repo/stale",
                    title: "Stale thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ]
        )
        try RuntimeSQLiteFixtureSupport.writeLogsDatabase(
            at: CodexPaths.logsSQLiteURL,
            logs: [
                .init(threadID: "thread-app", timestamp: 1_775_390_399, target: "codex_api::endpoint::responses_websocket"),
                .init(threadID: "thread-cli", timestamp: 1_775_390_398, target: "codex_api::sse::responses"),
                .init(threadID: "thread-subagent", timestamp: 1_775_390_397, target: "log", body: "session_task.turn streaming"),
                .init(threadID: "thread-stale", timestamp: 1_775_390_390, target: "codex_api::endpoint::responses_websocket"),
            ]
        )

        let snapshot = store.loadRunningThreads(
            now: now,
            recentActivityWindow: 5
        )

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.threads.map(\.threadID), ["thread-app", "thread-cli", "thread-subagent"])
        XCTAssertEqual(snapshot.threads.map(\.source), [
            "vscode",
            "cli",
            #"{"subagent":{"thread_spawn":{"parent_thread_id":"root","depth":1}}}"#,
        ])
    }

    func testLoadRunningThreadsSupportsLegacyLogsSchemaFallbackColumns() throws {
        let now = self.date("2026-04-05T12:00:00Z")
        let store = self.makeStore()
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-legacy",
                    source: "cli",
                    cwd: "/repo/legacy",
                    title: "Legacy thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ]
        )
        try RuntimeSQLiteFixtureSupport.writeLogsDatabase(
            at: CodexPaths.logsSQLiteURL,
            logs: [
                .init(threadID: "thread-legacy", timestamp: 1_775_390_399, target: "log", body: "session_task.turn live"),
            ],
            schema: .legacyCreatedAtAndBody
        )

        let snapshot = store.loadRunningThreads(
            now: now,
            recentActivityWindow: 5
        )

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.threads.map(\.threadID), ["thread-legacy"])
    }

    func testLoadRunningThreadsPrefersNewestLogsDatabaseVersion() throws {
        let now = self.date("2026-04-05T12:00:00Z")
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-new-logs-db",
                    source: "cli",
                    cwd: "/repo/new-logs",
                    title: "New logs db thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ]
        )

        let staleLogsURL = CodexPaths.codexRoot.appendingPathComponent("logs_1.sqlite")
        FileManager.default.createFile(atPath: staleLogsURL.path, contents: Data())

        let newestLogsURL = CodexPaths.codexRoot.appendingPathComponent("logs_2.sqlite")
        try RuntimeSQLiteFixtureSupport.writeLogsDatabase(
            at: newestLogsURL,
            logs: [
                .init(
                    threadID: "thread-new-logs-db",
                    timestamp: 1_775_390_399,
                    target: "log",
                    body: "session_task.turn live"
                ),
            ]
        )

        let store = self.makeStore()
        let snapshot = store.loadRunningThreads(
            now: now,
            recentActivityWindow: 5
        )

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.threads.map(\.threadID), ["thread-new-logs-db"])
        XCTAssertEqual(CodexPaths.logsSQLiteURL.lastPathComponent, "logs_2.sqlite")
    }

    func testLoadRunningThreadsRefreshesResolvedLogsDatabaseBetweenLoads() throws {
        let now = self.date("2026-04-05T12:00:00Z")
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-rotated-logs-db",
                    source: "cli",
                    cwd: "/repo/rotated",
                    title: "Rotated logs db thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ]
        )

        let originalLogsURL = CodexPaths.codexRoot.appendingPathComponent("logs_2.sqlite")
        try RuntimeSQLiteFixtureSupport.writeLogsDatabase(
            at: originalLogsURL,
            logs: []
        )

        let store = CodexThreadRuntimeStore()

        try FileManager.default.removeItem(at: originalLogsURL)

        let rotatedLogsURL = CodexPaths.codexRoot.appendingPathComponent("logs_3.sqlite")
        try RuntimeSQLiteFixtureSupport.writeLogsDatabase(
            at: rotatedLogsURL,
            logs: [
                .init(
                    threadID: "thread-rotated-logs-db",
                    timestamp: 1_775_390_399,
                    target: "log",
                    body: "session_task.turn live"
                ),
            ]
        )

        let snapshot = store.loadRunningThreads(
            now: now,
            recentActivityWindow: 5
        )

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.threads.map(\.threadID), ["thread-rotated-logs-db"])
        XCTAssertEqual(CodexPaths.logsSQLiteURL.lastPathComponent, "logs_3.sqlite")
    }

    func testLoadRunningThreadsReturnsUnavailableForIncompatibleLogsSchema() throws {
        let store = self.makeStore()
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-broken",
                    source: "cli",
                    cwd: "/repo/broken",
                    title: "Broken thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ]
        )
        try RuntimeSQLiteFixtureSupport.writeLogsDatabase(
            at: CodexPaths.logsSQLiteURL,
            logs: [],
            schema: .incompatibleMissingBody
        )

        let snapshot = store.loadRunningThreads(
            now: self.date("2026-04-05T12:00:00Z"),
            recentActivityWindow: 5
        )

        guard case .incompatibleSchema = snapshot.unavailableReason else {
            return XCTFail("expected incompatible schema, got \(String(describing: snapshot.unavailableReason))")
        }
        XCTAssertTrue(snapshot.threads.isEmpty)
    }

    func testLoadRunningThreadsReturnsUnavailableForMissingLogsTable() throws {
        let store = self.makeStore()
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-empty-logs-db",
                    source: "cli",
                    cwd: "/repo/empty",
                    title: "Empty logs db thread",
                    createdAt: 1,
                    updatedAt: 1
                ),
            ]
        )
        FileManager.default.createFile(
            atPath: CodexPaths.logsSQLiteURL.path,
            contents: Data()
        )

        let snapshot = store.loadRunningThreads(
            now: self.date("2026-04-05T12:00:00Z"),
            recentActivityWindow: 5
        )

        guard case let .missingTable(database, table) = snapshot.unavailableReason else {
            return XCTFail("expected missing table, got \(String(describing: snapshot.unavailableReason))")
        }
        XCTAssertEqual(database, CodexPaths.logsSQLiteURL.lastPathComponent)
        XCTAssertEqual(table, "logs")
        XCTAssertTrue(snapshot.threads.isEmpty)
    }

    func testLoadMostRecentThreadPrefersDesktopSource() throws {
        let store = self.makeStore()
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-cli",
                    source: "cli",
                    cwd: "/repo/cli",
                    title: "CLI thread",
                    createdAt: 1,
                    updatedAt: 100
                ),
                .init(
                    id: "thread-vscode",
                    source: "vscode",
                    cwd: "/repo/app",
                    title: "Desktop thread",
                    createdAt: 1,
                    updatedAt: 90
                ),
            ]
        )

        let thread = store.loadMostRecentThread()

        XCTAssertEqual(thread?.threadID, "thread-vscode")
        XCTAssertEqual(thread?.source, "vscode")
    }

    func testUpdateThreadLaunchConfigurationCanBeRestoredAfterProviderSwitch() throws {
        let store = self.makeStore()
        try RuntimeSQLiteFixtureSupport.writeStateDatabase(
            at: CodexPaths.stateSQLiteURL,
            threads: [
                .init(
                    id: "thread-vscode",
                    source: "vscode",
                    cwd: "/repo/app",
                    title: "Desktop thread",
                    createdAt: 1,
                    updatedAt: 90,
                    modelProvider: "openai",
                    model: "gpt-5.4",
                    reasoningEffort: "xhigh"
                ),
            ]
        )

        let original = try XCTUnwrap(
            store.loadThreadLaunchConfiguration(threadID: "thread-vscode")
        )
        XCTAssertEqual(original.modelProvider, "openai")
        XCTAssertEqual(original.model, "gpt-5.4")
        XCTAssertEqual(original.reasoningEffort, "xhigh")

        let snapshot = try XCTUnwrap(
            store.updateThreadLaunchConfigurationIfPossible(
                threadID: "thread-vscode",
                modelProvider: "ccodexr-compatible",
                model: "gpt-5.4-mini",
                reasoningEffort: "high"
            )
        )
        XCTAssertEqual(snapshot, original)

        let updated = try XCTUnwrap(
            store.loadThreadLaunchConfiguration(threadID: "thread-vscode")
        )
        XCTAssertEqual(updated.modelProvider, "ccodexr-compatible")
        XCTAssertEqual(updated.model, "gpt-5.4-mini")
        XCTAssertEqual(updated.reasoningEffort, "high")

        store.restoreThreadLaunchConfigurationIfPossible(snapshot)

        let restored = try XCTUnwrap(
            store.loadThreadLaunchConfiguration(threadID: "thread-vscode")
        )
        XCTAssertEqual(restored, original)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }

    private func makeStore() -> CodexThreadRuntimeStore {
        CodexThreadRuntimeStore(
            stateDBURL: CodexPaths.stateSQLiteURL,
            logsDBURL: CodexPaths.logsSQLiteURL
        )
    }
}
