import Foundation
import XCTest

final class LocalCostSummaryServiceTests: CodexBarTestCase {
    func testLoadAggregatesSessionsAcrossFastAndSlowPaths() throws {
        let home = try self.makeCodexHome()
        let store = SessionLogStore(
            codexRootURL: home.appendingPathComponent(".codex", isDirectory: true),
            persistedCacheURL: home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        )
        let service = LocalCostSummaryService(
            sessionLogStore: store,
            calendar: self.utcCalendar()
        )

        try self.writeFastSession(
            directory: home.appendingPathComponent(".codex/sessions", isDirectory: true),
            fileName: "today-fast.jsonl",
            id: "today-fast",
            timestamp: "2026-04-05T08:00:00Z",
            model: "gpt-5.4",
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 50
        )
        try self.writeSlowSession(
            directory: home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            fileName: "recent-slow.jsonl",
            id: "recent-slow",
            timestamp: "2026-04-03T09:00:00Z",
            model: "gpt-5-mini",
            inputTokens: 200,
            cachedInputTokens: 50,
            outputTokens: 40
        )
        try self.writeFastSession(
            directory: home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            fileName: "unsupported.jsonl",
            id: "unsupported",
            timestamp: "2026-03-01T09:00:00Z",
            model: "unknown-model",
            inputTokens: 999,
            cachedInputTokens: 0,
            outputTokens: 999
        )

        let summary = service.load(now: self.date("2026-04-05T12:00:00Z"))

        XCTAssertEqual(summary.todayTokens, 150)
        XCTAssertEqual(summary.last30DaysTokens, 390)
        XCTAssertEqual(summary.lifetimeTokens, 2_388)
        XCTAssertEqual(summary.dailyEntries.count, 3)
        XCTAssertEqual(summary.todayEntries.count, 1)
        XCTAssertEqual(summary.todayChartEntries.count, 4)

        XCTAssertEqual(summary.todayCostUSD, 0.000955, accuracy: 1e-12)
        XCTAssertEqual(summary.last30DaysCostUSD, 0.00107375, accuracy: 1e-12)
        XCTAssertEqual(summary.lifetimeCostUSD, 0.00107375, accuracy: 1e-12)

        XCTAssertEqual(summary.todayEntries[0].timestamp, self.date("2026-04-05T08:00:00Z"))
        XCTAssertEqual(summary.todayEntries[0].model, "gpt-5.4")
        XCTAssertEqual(summary.todayEntries[0].requestTokens, 100)
        XCTAssertEqual(summary.todayEntries[0].cachedRequestTokens, 20)
        XCTAssertEqual(summary.todayEntries[0].responseTokens, 50)
        XCTAssertEqual(summary.todayEntries[0].totalTokens, 150)
        XCTAssertEqual(summary.todayEntries[0].costUSD, 0.000955, accuracy: 1e-12)
        XCTAssertEqual(summary.todayChartEntries[0].startDate, self.date("2026-04-05T08:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[0].endDate, self.date("2026-04-05T09:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[0].totalTokens, 150)
        XCTAssertEqual(summary.todayChartEntries[0].costUSD, 0.000955, accuracy: 1e-12)
        XCTAssertEqual(summary.todayChartEntries[3].startDate, self.date("2026-04-05T11:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[3].endDate, self.date("2026-04-05T12:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[3].totalTokens, 0)
        XCTAssertEqual(summary.todayChartEntries[3].costUSD, 0, accuracy: 1e-12)

        XCTAssertEqual(summary.dailyEntries[0].date, self.date("2026-04-05T00:00:00Z"))
        XCTAssertEqual(summary.dailyEntries[0].totalTokens, 150)
        XCTAssertEqual(summary.dailyEntries[0].costUSD, 0.000955, accuracy: 1e-12)

        XCTAssertEqual(summary.dailyEntries[1].date, self.date("2026-04-03T00:00:00Z"))
        XCTAssertEqual(summary.dailyEntries[1].totalTokens, 240)
        XCTAssertEqual(summary.dailyEntries[1].costUSD, 0.00011875, accuracy: 1e-12)

        XCTAssertEqual(summary.dailyEntries[2].date, self.date("2026-03-01T00:00:00Z"))
        XCTAssertEqual(summary.dailyEntries[2].totalTokens, 1_998)
        XCTAssertEqual(summary.dailyEntries[2].costUSD, 0, accuracy: 1e-12)
    }

    func testLoadRefreshesChangedSessionFileInsteadOfServingStaleCache() throws {
        let home = try self.makeCodexHome()
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let sessionDirectory = codexRoot.appendingPathComponent("sessions", isDirectory: true)
        let sessionFileURL = sessionDirectory.appendingPathComponent("mutable.jsonl")
        let cacheURL = home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        let store = SessionLogStore(codexRootURL: codexRoot, persistedCacheURL: cacheURL)
        let service = LocalCostSummaryService(
            sessionLogStore: store,
            calendar: self.utcCalendar()
        )

        try self.writeFastSession(
            directory: sessionDirectory,
            fileName: "mutable.jsonl",
            id: "mutable",
            timestamp: "2026-04-05T08:00:00Z",
            model: "gpt-5.4-mini",
            inputTokens: 100,
            cachedInputTokens: 10,
            outputTokens: 20
        )
        try FileManager.default.setAttributes(
            [.modificationDate: self.date("2026-04-05T08:00:30Z")],
            ofItemAtPath: sessionFileURL.path
        )

        let initialSummary = service.load(now: self.date("2026-04-05T12:00:00Z"))
        XCTAssertEqual(initialSummary.todayTokens, 120)
        XCTAssertEqual(initialSummary.todayCostUSD, 0.00015825, accuracy: 1e-12)

        try self.writeFastSession(
            directory: sessionDirectory,
            fileName: "mutable.jsonl",
            id: "mutable",
            timestamp: "2026-04-05T08:00:00Z",
            model: "gpt-5.4-mini",
            inputTokens: 200,
            cachedInputTokens: 10,
            outputTokens: 50
        )
        try FileManager.default.setAttributes(
            [.modificationDate: self.date("2026-04-05T08:01:30Z")],
            ofItemAtPath: sessionFileURL.path
        )

        let updatedSummary = service.load(now: self.date("2026-04-05T12:00:00Z"))
        XCTAssertEqual(updatedSummary.todayTokens, 250)
        XCTAssertEqual(updatedSummary.todayCostUSD, 0.00036825, accuracy: 1e-12)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testLoadAttributesCrossDaySessionUsageToEventDay() throws {
        let home = try self.makeCodexHome()
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let store = SessionLogStore(
            codexRootURL: codexRoot,
            persistedCacheURL: home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        )
        let service = LocalCostSummaryService(
            sessionLogStore: store,
            calendar: self.utcCalendar()
        )

        try self.writeSession(
            directory: codexRoot.appendingPathComponent("sessions", isDirectory: true),
            fileName: "cross-day.jsonl",
            lines: [
                #"{"payload":{"type":"session_meta","id":"cross-day","timestamp":"2026-04-04T23:50:00Z"}}"#,
                #"{"payload":{"type":"turn_context","model":"gpt-5.4"}}"#,
                #"{"timestamp":"2026-04-04T23:55:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":20},"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":20}}}}"#,
                #"{"timestamp":"2026-04-05T01:10:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":170,"cached_input_tokens":30,"output_tokens":30},"last_token_usage":{"input_tokens":70,"cached_input_tokens":10,"output_tokens":10}}}}"#,
            ]
        )

        let summary = service.load(now: self.date("2026-04-05T12:00:00Z"))

        XCTAssertEqual(summary.todayTokens, 80)
        XCTAssertEqual(summary.last30DaysTokens, 200)
        XCTAssertEqual(summary.lifetimeTokens, 200)
        XCTAssertEqual(summary.dailyEntries.count, 2)
        XCTAssertEqual(summary.todayEntries.count, 1)

        XCTAssertEqual(summary.dailyEntries[0].date, self.date("2026-04-05T00:00:00Z"))
        XCTAssertEqual(summary.dailyEntries[0].totalTokens, 80)
        XCTAssertEqual(summary.dailyEntries[0].costUSD, 0.0003025, accuracy: 1e-12)

        XCTAssertEqual(summary.dailyEntries[1].date, self.date("2026-04-04T00:00:00Z"))
        XCTAssertEqual(summary.dailyEntries[1].totalTokens, 120)
        XCTAssertEqual(summary.dailyEntries[1].costUSD, 0.000505, accuracy: 1e-12)

        XCTAssertEqual(summary.todayCostUSD, 0.0003025, accuracy: 1e-12)
        XCTAssertEqual(summary.last30DaysCostUSD, 0.0008075, accuracy: 1e-12)
        XCTAssertEqual(summary.lifetimeCostUSD, 0.0008075, accuracy: 1e-12)

        XCTAssertEqual(summary.todayEntries[0].timestamp, self.date("2026-04-05T01:10:00Z"))
        XCTAssertEqual(summary.todayEntries[0].requestTokens, 70)
        XCTAssertEqual(summary.todayEntries[0].cachedRequestTokens, 10)
        XCTAssertEqual(summary.todayEntries[0].responseTokens, 10)
        XCTAssertEqual(summary.todayEntries[0].totalTokens, 80)
        XCTAssertEqual(summary.todayChartEntries.count, 4)
        XCTAssertTrue(summary.todayChartEntries.allSatisfy { $0.totalTokens == 0 })
        XCTAssertTrue(summary.todayChartEntries.allSatisfy { abs($0.costUSD) < 1e-12 })
    }

    func testLoadBuildsTodayEntriesForEachIncrementalUsageEvent() throws {
        let home = try self.makeCodexHome()
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let store = SessionLogStore(
            codexRootURL: codexRoot,
            persistedCacheURL: home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        )
        let service = LocalCostSummaryService(
            sessionLogStore: store,
            calendar: self.utcCalendar()
        )

        try self.writeSession(
            directory: codexRoot.appendingPathComponent("sessions", isDirectory: true),
            fileName: "multi-event.jsonl",
            lines: [
                #"{"payload":{"type":"session_meta","id":"multi-event","timestamp":"2026-04-05T08:00:00Z"}}"#,
                #"{"payload":{"type":"turn_context","model":"gpt-5.4-mini"}}"#,
                #"{"timestamp":"2026-04-05T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":30},"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":30}}}}"#,
                #"{"timestamp":"2026-04-05T08:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"cached_input_tokens":30,"output_tokens":55},"last_token_usage":{"input_tokens":60,"cached_input_tokens":10,"output_tokens":25}}}}"#,
            ]
        )

        let summary = service.load(now: self.date("2026-04-05T12:00:00Z"))

        XCTAssertEqual(summary.todayEntries.count, 2)
        XCTAssertEqual(summary.todayTokens, 235)

        XCTAssertEqual(summary.todayEntries[0].timestamp, self.date("2026-04-05T08:05:00Z"))
        XCTAssertEqual(summary.todayEntries[0].requestTokens, 60)
        XCTAssertEqual(summary.todayEntries[0].cachedRequestTokens, 10)
        XCTAssertEqual(summary.todayEntries[0].responseTokens, 25)
        XCTAssertEqual(summary.todayEntries[0].totalTokens, 85)
        XCTAssertEqual(summary.todayEntries[0].costUSD, 0.00015075, accuracy: 1e-12)

        XCTAssertEqual(summary.todayEntries[1].timestamp, self.date("2026-04-05T08:00:00Z"))
        XCTAssertEqual(summary.todayEntries[1].requestTokens, 120)
        XCTAssertEqual(summary.todayEntries[1].cachedRequestTokens, 20)
        XCTAssertEqual(summary.todayEntries[1].responseTokens, 30)
        XCTAssertEqual(summary.todayEntries[1].totalTokens, 150)
        XCTAssertEqual(summary.todayEntries[1].costUSD, 0.0002115, accuracy: 1e-12)
        XCTAssertEqual(summary.todayCostUSD, 0.00036225, accuracy: 1e-12)
        XCTAssertEqual(summary.todayChartEntries.count, 4)
        XCTAssertEqual(summary.todayChartEntries[0].startDate, self.date("2026-04-05T08:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[0].endDate, self.date("2026-04-05T09:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[0].totalTokens, 235)
        XCTAssertEqual(summary.todayChartEntries[0].costUSD, 0.00036225, accuracy: 1e-12)
        XCTAssertEqual(summary.todayChartEntries[3].startDate, self.date("2026-04-05T11:00:00Z"))
        XCTAssertEqual(summary.todayChartEntries[3].endDate, self.date("2026-04-05T12:00:00Z"))
    }

    func testLoadPricesUsageUsingPerEventModelAfterTurnContextSwitch() throws {
        let home = try self.makeCodexHome()
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let store = SessionLogStore(
            codexRootURL: codexRoot,
            persistedCacheURL: home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        )
        let service = LocalCostSummaryService(
            sessionLogStore: store,
            calendar: self.utcCalendar()
        )

        try self.writeSession(
            directory: codexRoot.appendingPathComponent("sessions", isDirectory: true),
            fileName: "model-switch.jsonl",
            lines: [
                #"{"payload":{"type":"session_meta","id":"model-switch","timestamp":"2026-04-05T08:00:00Z"}}"#,
                #"{"payload":{"type":"turn_context","model":"gpt-5.4-mini"}}"#,
                #"{"timestamp":"2026-04-05T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30},"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":30}}}}"#,
                #"{"payload":{"type":"turn_context","model":"gpt-5.4"}}"#,
                #"{"timestamp":"2026-04-05T08:05:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":30,"output_tokens":45},"last_token_usage":{"input_tokens":60,"cached_input_tokens":10,"output_tokens":15}}}}"#,
            ]
        )

        let summary = service.load(now: self.date("2026-04-05T12:00:00Z"))

        XCTAssertEqual(summary.todayEntries.count, 2)
        XCTAssertEqual(summary.todayTokens, 205)
        XCTAssertEqual(summary.todayCostUSD, 0.000549, accuracy: 1e-12)

        XCTAssertEqual(summary.todayEntries[0].model, "gpt-5.4")
        XCTAssertEqual(summary.todayEntries[0].requestTokens, 60)
        XCTAssertEqual(summary.todayEntries[0].responseTokens, 15)
        XCTAssertTrue(summary.todayEntries[0].hasKnownPricing)
        XCTAssertEqual(summary.todayEntries[0].costUSD, 0.0003525, accuracy: 1e-12)

        XCTAssertEqual(summary.todayEntries[1].model, "gpt-5.4-mini")
        XCTAssertEqual(summary.todayEntries[1].requestTokens, 100)
        XCTAssertEqual(summary.todayEntries[1].responseTokens, 30)
        XCTAssertTrue(summary.todayEntries[1].hasKnownPricing)
        XCTAssertEqual(summary.todayEntries[1].costUSD, 0.0001965, accuracy: 1e-12)
    }

    func testLoadKeepsUnknownModelTokensInSummariesAndMarksEntryUnpriced() throws {
        let home = try self.makeCodexHome()
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let store = SessionLogStore(
            codexRootURL: codexRoot,
            persistedCacheURL: home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        )
        let service = LocalCostSummaryService(
            sessionLogStore: store,
            calendar: self.utcCalendar()
        )

        try self.writeSession(
            directory: codexRoot.appendingPathComponent("sessions", isDirectory: true),
            fileName: "unknown-model.jsonl",
            lines: [
                #"{"payload":{"type":"session_meta","id":"unknown-model","timestamp":"2026-04-05T08:00:00Z"}}"#,
                #"{"payload":{"type":"turn_context","model":"custom-provider-preview"}}"#,
                #"{"timestamp":"2026-04-05T08:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":30},"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":30}}}}"#,
            ]
        )

        let summary = service.load(now: self.date("2026-04-05T12:00:00Z"))

        XCTAssertEqual(summary.todayTokens, 150)
        XCTAssertEqual(summary.last30DaysTokens, 150)
        XCTAssertEqual(summary.lifetimeTokens, 150)
        XCTAssertEqual(summary.todayCostUSD, 0, accuracy: 1e-12)
        XCTAssertEqual(summary.todayEntries.count, 1)
        XCTAssertEqual(summary.todayEntries[0].model, "custom-provider-preview")
        XCTAssertFalse(summary.todayEntries[0].hasKnownPricing)
        XCTAssertEqual(summary.todayEntries[0].costUSD, 0, accuracy: 1e-12)
        XCTAssertEqual(summary.todayChartEntries.count, 4)
        XCTAssertFalse(summary.todayChartEntries[0].hasKnownPricing)
        XCTAssertEqual(summary.todayChartEntries[0].totalTokens, 150)
        XCTAssertEqual(summary.todayChartEntries[0].costUSD, 0, accuracy: 1e-12)
    }

    func testLoadUsesPersistedSessionCacheAcrossRestartWhenModificationDateHasFractionalSeconds() throws {
        let home = try self.makeCodexHome()
        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        let cacheURL = home.appendingPathComponent(".codexbar/test-cost-session-cache.json")
        let sessionDirectory = codexRoot.appendingPathComponent("sessions", isDirectory: true)
        let fileURL = sessionDirectory.appendingPathComponent("fractional-mtime.jsonl")

        try self.writeFastSession(
            directory: sessionDirectory,
            fileName: "fractional-mtime.jsonl",
            id: "fractional-mtime",
            timestamp: "2026-04-05T08:00:00Z",
            model: "gpt-5.4-mini",
            inputTokens: 120,
            cachedInputTokens: 20,
            outputTokens: 30
        )

        let fractionalModificationDate = Date(timeIntervalSince1970: 1_775_376_112.654321)
        try FileManager.default.setAttributes(
            [.modificationDate: fractionalModificationDate],
            ofItemAtPath: fileURL.path
        )

        let firstService = LocalCostSummaryService(
            sessionLogStore: SessionLogStore(codexRootURL: codexRoot, persistedCacheURL: cacheURL),
            calendar: self.utcCalendar()
        )
        let firstSummary = firstService.load(now: self.date("2026-04-05T12:00:00Z"))
        XCTAssertEqual(firstSummary.todayTokens, 150)
        XCTAssertEqual(firstSummary.todayEntries.count, 1)

        let originalSize = try Data(contentsOf: fileURL).count
        let invalidData = Data(repeating: UInt8(ascii: "x"), count: originalSize)
        try invalidData.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: fractionalModificationDate],
            ofItemAtPath: fileURL.path
        )

        let secondService = LocalCostSummaryService(
            sessionLogStore: SessionLogStore(codexRootURL: codexRoot, persistedCacheURL: cacheURL),
            calendar: self.utcCalendar()
        )
        let secondSummary = secondService.load(now: self.date("2026-04-05T12:00:00Z"))

        XCTAssertEqual(secondSummary.todayTokens, 150)
        XCTAssertEqual(secondSummary.todayEntries.count, 1)
        XCTAssertEqual(secondSummary.todayEntries[0].requestTokens, 120)
        XCTAssertEqual(secondSummary.todayEntries[0].cachedRequestTokens, 20)
        XCTAssertEqual(secondSummary.todayEntries[0].responseTokens, 30)
    }

    private func makeCodexHome() throws -> URL {
        let home = try XCTUnwrap(self.temporaryHomeURL())
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex/sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        return home
    }

    private func temporaryHomeURL() -> URL? {
        let home = ProcessInfo.processInfo.environment["CODEXBAR_HOME"]
        guard let home, home.isEmpty == false else { return nil }
        return URL(fileURLWithPath: home, isDirectory: true)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
    }

    private func writeFastSession(
        directory: URL,
        fileName: String,
        id: String,
        timestamp: String,
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) throws {
        let content = [
            #"{"payload":{"type":"session_meta","id":"\#(id)","timestamp":"\#(timestamp)"}}"#,
            #"{"payload":{"type":"turn_context","model":"\#(model)"}}"#,
            #"{"payload":{"type":"event_msg","kind":"token_count","total_token_usage":{"input_tokens":\#(inputTokens),"cached_input_tokens":\#(cachedInputTokens),"output_tokens":\#(outputTokens)}}}"#,
        ].joined(separator: "\n") + "\n"

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.write(
            to: directory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSlowSession(
        directory: URL,
        fileName: String,
        id: String,
        timestamp: String,
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) throws {
        let content = [
            #"{"payload":{"type":"session_meta","id":"\#(id)","timestamp":"\#(timestamp)"}}"#,
            #"{"payload":{"type":"turn_context","model":"\#(model)"}}"#,
            #"{"wrapper":{"type":"event_msg"},"payload":{"type":"token_count","kind":"token_count","info":{"total_token_usage": {"input_tokens": \#(inputTokens), "cached_input_tokens": \#(cachedInputTokens), "output_tokens": \#(outputTokens)}}}}"#,
        ].joined(separator: "\n") + "\n"

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try content.write(
            to: directory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSession(
        directory: URL,
        fileName: String,
        lines: [String]
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }
}
