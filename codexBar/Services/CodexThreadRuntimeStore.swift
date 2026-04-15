import Foundation
import SQLite3

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CodexThreadRuntimeStore {
    struct RuntimeLogRule: Equatable {
        let target: String?
        let bodySubstrings: [String]

        init(target: String? = nil, bodySubstrings: [String] = []) {
            self.target = target
            self.bodySubstrings = bodySubstrings
        }
    }

    private struct ResolvedLogsSchema {
        let timestampColumn: String
        let bodyColumn: String
    }

    struct RuntimeThread: Equatable {
        let threadID: String
        let source: String
        let cwd: String
        let title: String
        let lastRuntimeAt: Date
    }

    struct ThreadLaunchConfiguration: Equatable {
        let threadID: String
        let modelProvider: String
        let model: String?
        let reasoningEffort: String?
    }

    enum UnavailableReason: Error, Equatable {
        case missingDatabase(name: String)
        case missingTable(database: String, table: String)
        case incompatibleSchema(message: String)
        case queryFailed(message: String)

        var diagnosticMessage: String {
            switch self {
            case let .missingDatabase(name):
                return "missing runtime database: \(name)"
            case let .missingTable(database, table):
                return "runtime database missing table: \(database).\(table)"
            case let .incompatibleSchema(message):
                return "runtime database schema incompatible: \(message)"
            case let .queryFailed(message):
                return "runtime database query failed: \(message)"
            }
        }
    }

    struct Snapshot: Equatable {
        let threads: [RuntimeThread]
        let recentActivityWindow: TimeInterval
        let unavailableReason: UnavailableReason?

        static func available(
            threads: [RuntimeThread],
            recentActivityWindow: TimeInterval
        ) -> Snapshot {
            Snapshot(
                threads: threads,
                recentActivityWindow: recentActivityWindow,
                unavailableReason: nil
            )
        }

        static func unavailable(
            _ reason: UnavailableReason,
            recentActivityWindow: TimeInterval
        ) -> Snapshot {
            Snapshot(
                threads: [],
                recentActivityWindow: recentActivityWindow,
                unavailableReason: reason
            )
        }

        var isUnavailable: Bool {
            self.unavailableReason != nil
        }
    }

    static let shared = CodexThreadRuntimeStore()
    static let defaultRecentActivityWindow: TimeInterval = 5
    static let runtimeLogRules: [RuntimeLogRule] = [
        .init(target: "session_task.turn"),
        .init(target: "codex_api::endpoint::responses_websocket"),
        .init(target: "codex_api::sse::responses"),
        .init(
            target: "codex_core::stream_events_utils",
            bodySubstrings: ["session_loop", "submission_dispatch"]
        ),
        .init(target: "log", bodySubstrings: ["session_task.turn"]),
        .init(target: "codex_otel.log_only", bodySubstrings: ["session_task.turn"]),
        .init(target: "codex_otel.trace_safe", bodySubstrings: ["session_task.turn"]),
    ]

    private let stateDBURLProvider: () -> URL
    private let logsDBURLProvider: () -> URL
    private let fileManager: FileManager

    init(
        stateDBURL: @autoclosure @escaping () -> URL = CodexPaths.stateSQLiteURL,
        logsDBURL: @autoclosure @escaping () -> URL = CodexPaths.logsSQLiteURL,
        fileManager: FileManager = .default
    ) {
        self.stateDBURLProvider = stateDBURL
        self.logsDBURLProvider = logsDBURL
        self.fileManager = fileManager
    }

    func loadRunningThreads(
        now: Date = Date(),
        recentActivityWindow: TimeInterval = Self.defaultRecentActivityWindow
    ) -> Snapshot {
        let sanitizedWindow = max(0, recentActivityWindow)
        // Codex may rotate versioned sqlite filenames while codexbar stays alive.
        let stateDBURL = self.stateDBURLProvider()
        let logsDBURL = self.logsDBURLProvider()

        do {
            try self.requireDatabase(at: stateDBURL)
            try self.requireDatabase(at: logsDBURL)

            let lowerBoundTimestamp = Int64(floor(now.timeIntervalSince1970 - sanitizedWindow))
            let runtimeMatches = try self.loadRuntimeLogMatches(
                since: lowerBoundTimestamp,
                logsDBURL: logsDBURL
            )
            guard runtimeMatches.isEmpty == false else {
                return .available(threads: [], recentActivityWindow: sanitizedWindow)
            }

            let threads = try self.loadThreads(
                matching: runtimeMatches,
                stateDBURL: stateDBURL
            )
            return .available(
                threads: threads.sorted {
                    if $0.lastRuntimeAt != $1.lastRuntimeAt {
                        return $0.lastRuntimeAt > $1.lastRuntimeAt
                    }
                    return $0.threadID < $1.threadID
                },
                recentActivityWindow: sanitizedWindow
            )
        } catch let reason as UnavailableReason {
            NSLog("ccodexr running-thread runtime unavailable: %@", reason.diagnosticMessage)
            return .unavailable(reason, recentActivityWindow: sanitizedWindow)
        } catch {
            let reason = UnavailableReason.queryFailed(message: error.localizedDescription)
            NSLog("ccodexr running-thread runtime unavailable: %@", reason.diagnosticMessage)
            return .unavailable(reason, recentActivityWindow: sanitizedWindow)
        }
    }

    func loadMostRecentThread(preferredSources: [String] = ["vscode"]) -> RuntimeThread? {
        let stateDBURL = self.stateDBURLProvider()

        do {
            try self.requireDatabase(at: stateDBURL)
            if let preferredThread = try self.loadMostRecentThread(
                preferredSources: preferredSources,
                stateDBURL: stateDBURL
            ) {
                return preferredThread
            }
            return try self.loadMostRecentThread(
                preferredSources: [],
                stateDBURL: stateDBURL
            )
        } catch {
            return nil
        }
    }

    func loadThreadLaunchConfiguration(threadID: String) -> ThreadLaunchConfiguration? {
        let sanitizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedThreadID.isEmpty == false else { return nil }

        let stateDBURL = self.stateDBURLProvider()
        do {
            try self.requireDatabase(at: stateDBURL)
            return try self.withReadConnection(at: stateDBURL) { db in
                try self.validateSchema(
                    in: db,
                    table: "threads",
                    requiredColumns: ["id", "model_provider", "model", "reasoning_effort", "archived"],
                    databaseName: stateDBURL.lastPathComponent
                )
                return try self.loadThreadLaunchConfiguration(
                    threadID: sanitizedThreadID,
                    in: db
                )
            }
        } catch {
            return nil
        }
    }

    @discardableResult
    func updateThreadLaunchConfigurationIfPossible(
        threadID: String,
        modelProvider: String,
        model: String?,
        reasoningEffort: String?
    ) -> ThreadLaunchConfiguration? {
        let sanitizedThreadID = threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedModelProvider = modelProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedThreadID.isEmpty == false, sanitizedModelProvider.isEmpty == false else { return nil }

        let stateDBURL = self.stateDBURLProvider()
        do {
            try self.requireDatabase(at: stateDBURL)
            return try self.withWriteConnection(at: stateDBURL) { db in
                try self.validateSchema(
                    in: db,
                    table: "threads",
                    requiredColumns: ["id", "model_provider", "model", "reasoning_effort", "archived"],
                    databaseName: stateDBURL.lastPathComponent
                )

                guard let previous = try self.loadThreadLaunchConfiguration(
                    threadID: sanitizedThreadID,
                    in: db
                ) else {
                    return nil
                }

                let statement = try SQLiteStatement(
                    database: db,
                    sql: """
                    UPDATE threads
                    SET model_provider = ?, model = ?, reasoning_effort = ?
                    WHERE archived = 0 AND id = ?
                    """
                )
                try statement.bindText(sanitizedModelProvider, at: 1)
                try statement.bindNullableText(model, at: 2)
                try statement.bindNullableText(reasoningEffort, at: 3)
                try statement.bindText(sanitizedThreadID, at: 4)
                let stepResult = sqlite3_step(statement.handle)
                guard stepResult == SQLITE_DONE else {
                    throw UnavailableReason.queryFailed(
                        message: "failed updating thread launch configuration (\(stepResult))"
                    )
                }

                return previous
            }
        } catch let reason as UnavailableReason {
            NSLog("ccodexr failed to update thread launch configuration: %@", reason.diagnosticMessage)
            return nil
        } catch {
            NSLog("ccodexr failed to update thread launch configuration: %@", error.localizedDescription)
            return nil
        }
    }

    func restoreThreadLaunchConfigurationIfPossible(_ snapshot: ThreadLaunchConfiguration?) {
        guard let snapshot else { return }
        _ = self.updateThreadLaunchConfigurationIfPossible(
            threadID: snapshot.threadID,
            modelProvider: snapshot.modelProvider,
            model: snapshot.model,
            reasoningEffort: snapshot.reasoningEffort
        )
    }

    private func requireDatabase(at url: URL) throws {
        guard self.fileManager.fileExists(atPath: url.path) else {
            throw UnavailableReason.missingDatabase(name: url.lastPathComponent)
        }
    }

    private func loadRuntimeLogMatches(
        since lowerBoundTimestamp: Int64,
        logsDBURL: URL
    ) throws -> [String: Int64] {
        try self.withReadConnection(at: logsDBURL) { db in
            try self.requireTable(
                "logs",
                in: db,
                databaseName: logsDBURL.lastPathComponent
            )
            let availableColumns = try self.tableColumns(in: db, table: "logs")
            try self.validateRequiredColumns(
                availableColumns,
                requiredColumns: ["thread_id", "target"],
                databaseName: logsDBURL.lastPathComponent,
                table: "logs"
            )
            let resolvedSchema = try self.resolveLogsSchema(
                availableColumns: availableColumns,
                databaseName: logsDBURL.lastPathComponent
            )

            let sql = """
            SELECT thread_id, MAX(\(resolvedSchema.timestampColumn)) AS last_runtime_ts
            FROM logs
            WHERE thread_id IS NOT NULL
              AND \(resolvedSchema.timestampColumn) >= ?
              AND (\(Self.runtimeLogPredicateSQL(bodyColumn: resolvedSchema.bodyColumn)))
            GROUP BY thread_id
            ORDER BY last_runtime_ts DESC, thread_id ASC
            """

            let statement = try SQLiteStatement(database: db, sql: sql)
            try statement.bindInt64(lowerBoundTimestamp, at: 1)

            var matches: [String: Int64] = [:]
            while true {
                let stepResult = sqlite3_step(statement.handle)
                switch stepResult {
                case SQLITE_ROW:
                    guard let threadID = statement.text(at: 0), threadID.isEmpty == false else { continue }
                    matches[threadID] = statement.int64(at: 1)
                case SQLITE_DONE:
                    return matches
                default:
                    throw UnavailableReason.queryFailed(
                        message: "failed stepping recent runtime logs query (\(stepResult))"
                    )
                }
            }
        }
    }

    private func loadThreads(
        matching runtimeMatches: [String: Int64],
        stateDBURL: URL
    ) throws -> [RuntimeThread] {
        let threadIDs = runtimeMatches.keys.sorted()
        guard threadIDs.isEmpty == false else { return [] }

        return try self.withReadConnection(at: stateDBURL) { db in
            try self.validateSchema(
                in: db,
                table: "threads",
                requiredColumns: ["id", "source", "cwd", "title", "archived"],
                databaseName: stateDBURL.lastPathComponent
            )

            let placeholders = Array(repeating: "?", count: threadIDs.count).joined(separator: ", ")
            let sql = """
            SELECT id, source, cwd, title
            FROM threads
            WHERE archived = 0
              AND id IN (\(placeholders))
            """

            let statement = try SQLiteStatement(database: db, sql: sql)
            for (index, threadID) in threadIDs.enumerated() {
                try statement.bindText(threadID, at: Int32(index + 1))
            }

            var threads: [RuntimeThread] = []
            while true {
                let stepResult = sqlite3_step(statement.handle)
                switch stepResult {
                case SQLITE_ROW:
                    guard
                        let threadID = statement.text(at: 0),
                        let source = statement.text(at: 1),
                        let cwd = statement.text(at: 2),
                        let title = statement.text(at: 3),
                        let lastRuntimeTimestamp = runtimeMatches[threadID] else {
                        continue
                    }

                    threads.append(
                        RuntimeThread(
                            threadID: threadID,
                            source: source,
                            cwd: cwd,
                            title: title,
                            lastRuntimeAt: Date(timeIntervalSince1970: TimeInterval(lastRuntimeTimestamp))
                        )
                    )
                case SQLITE_DONE:
                    return threads
                default:
                    throw UnavailableReason.queryFailed(
                        message: "failed stepping runtime thread metadata query (\(stepResult))"
                    )
                }
            }
        }
    }

    private func loadMostRecentThread(
        preferredSources: [String],
        stateDBURL: URL
    ) throws -> RuntimeThread? {
        try self.withReadConnection(at: stateDBURL) { db in
            try self.validateSchema(
                in: db,
                table: "threads",
                requiredColumns: ["id", "source", "cwd", "title", "archived", "updated_at"],
                databaseName: stateDBURL.lastPathComponent
            )

            let sourcePredicate: String
            if preferredSources.isEmpty {
                sourcePredicate = ""
            } else {
                let placeholders = Array(repeating: "?", count: preferredSources.count).joined(separator: ", ")
                sourcePredicate = " AND source IN (\(placeholders))"
            }

            let statement = try SQLiteStatement(
                database: db,
                sql: """
                SELECT id, source, cwd, title, updated_at
                FROM threads
                WHERE archived = 0\(sourcePredicate)
                ORDER BY updated_at DESC, id DESC
                LIMIT 1
                """
            )

            for (index, source) in preferredSources.enumerated() {
                try statement.bindText(source, at: Int32(index + 1))
            }

            let stepResult = sqlite3_step(statement.handle)
            switch stepResult {
            case SQLITE_ROW:
                guard
                    let threadID = statement.text(at: 0),
                    let source = statement.text(at: 1),
                    let cwd = statement.text(at: 2),
                    let title = statement.text(at: 3)
                else {
                    return nil
                }
                return RuntimeThread(
                    threadID: threadID,
                    source: source,
                    cwd: cwd,
                    title: title,
                    lastRuntimeAt: Date(timeIntervalSince1970: TimeInterval(statement.int64(at: 4)))
                )
            case SQLITE_DONE:
                return nil
            default:
                throw UnavailableReason.queryFailed(
                    message: "failed stepping latest thread query (\(stepResult))"
                )
            }
        }
    }

    private func loadThreadLaunchConfiguration(
        threadID: String,
        in database: OpaquePointer
    ) throws -> ThreadLaunchConfiguration? {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            SELECT id, model_provider, model, reasoning_effort
            FROM threads
            WHERE archived = 0 AND id = ?
            LIMIT 1
            """
        )
        try statement.bindText(threadID, at: 1)

        let stepResult = sqlite3_step(statement.handle)
        switch stepResult {
        case SQLITE_ROW:
            guard let resolvedThreadID = statement.text(at: 0),
                  let modelProvider = statement.text(at: 1) else {
                return nil
            }
            return ThreadLaunchConfiguration(
                threadID: resolvedThreadID,
                modelProvider: modelProvider,
                model: statement.text(at: 2),
                reasoningEffort: statement.text(at: 3)
            )
        case SQLITE_DONE:
            return nil
        default:
            throw UnavailableReason.queryFailed(
                message: "failed loading thread launch configuration (\(stepResult))"
            )
        }
    }

    private func withReadConnection<T>(at url: URL, work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            let message: String
            if let database, let pointer = sqlite3_errmsg(database) {
                message = String(cString: pointer)
            } else {
                message = "unable to open \(url.lastPathComponent)"
            }
            sqlite3_close(database)
            throw UnavailableReason.queryFailed(message: message)
        }

        defer { sqlite3_close(database) }
        return try work(database)
    }

    private func withWriteConnection<T>(at url: URL, work: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message: String
            if let database, let pointer = sqlite3_errmsg(database) {
                message = String(cString: pointer)
            } else {
                message = "unable to open \(url.lastPathComponent) for writing"
            }
            sqlite3_close(database)
            throw UnavailableReason.queryFailed(message: message)
        }

        sqlite3_busy_timeout(database, 1_500)
        defer { sqlite3_close(database) }
        return try work(database)
    }

    private func validateSchema(
        in database: OpaquePointer,
        table: String,
        requiredColumns: Set<String>,
        databaseName: String
    ) throws {
        try self.requireTable(
            table,
            in: database,
            databaseName: databaseName
        )
        let availableColumns = try self.tableColumns(in: database, table: table)
        try self.validateRequiredColumns(
            availableColumns,
            requiredColumns: requiredColumns,
            databaseName: databaseName,
            table: table
        )
    }

    private func requireTable(
        _ table: String,
        in database: OpaquePointer,
        databaseName: String
    ) throws {
        guard try self.tableExists(named: table, in: database) else {
            throw UnavailableReason.missingTable(
                database: databaseName,
                table: table
            )
        }
    }

    private func validateRequiredColumns(
        _ availableColumns: Set<String>,
        requiredColumns: Set<String>,
        databaseName: String,
        table: String
    ) throws {
        let missingColumns = requiredColumns.subtracting(availableColumns)
        guard missingColumns.isEmpty else {
            let missing = missingColumns.sorted().joined(separator: ", ")
            throw UnavailableReason.incompatibleSchema(
                message: "\(databaseName).\(table) missing columns: \(missing)"
            )
        }
    }

    private func resolveLogsSchema(
        availableColumns: Set<String>,
        databaseName: String
    ) throws -> ResolvedLogsSchema {
        let timestampColumn = ["ts", "created_at"].first(where: { availableColumns.contains($0) })
        let bodyColumn = ["feedback_log_body", "body"].first(where: { availableColumns.contains($0) })

        guard let timestampColumn, let bodyColumn else {
            throw UnavailableReason.incompatibleSchema(
                message: "\(databaseName).logs missing columns: ts|created_at and feedback_log_body|body"
            )
        }

        return ResolvedLogsSchema(timestampColumn: timestampColumn, bodyColumn: bodyColumn)
    }

    private func tableExists(named table: String, in database: OpaquePointer) throws -> Bool {
        let statement = try SQLiteStatement(
            database: database,
            sql: """
            SELECT 1
            FROM sqlite_master
            WHERE type = 'table' AND name = ?
            LIMIT 1
            """
        )
        try statement.bindText(table, at: 1)

        let stepResult = sqlite3_step(statement.handle)
        switch stepResult {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw UnavailableReason.queryFailed(
                message: "failed checking sqlite_master for table \(table) (\(stepResult))"
            )
        }
    }

    private func tableColumns(in database: OpaquePointer, table: String) throws -> Set<String> {
        let statement = try SQLiteStatement(
            database: database,
            sql: "PRAGMA table_info(\(table))"
        )

        var columns: Set<String> = []
        while true {
            let stepResult = sqlite3_step(statement.handle)
            switch stepResult {
            case SQLITE_ROW:
                if let column = statement.text(at: 1) {
                    columns.insert(column)
                }
            case SQLITE_DONE:
                return columns
            default:
                throw UnavailableReason.queryFailed(
                    message: "failed inspecting schema for \(table) (\(stepResult))"
                )
            }
        }
    }

    private static func runtimeLogPredicateSQL(bodyColumn: String) -> String {
        self.runtimeLogRules
            .map { rule in
                if let target = rule.target?.replacingOccurrences(of: "'", with: "''"),
                   rule.bodySubstrings.isEmpty {
                    return "target = '\(target)'"
                }

                let bodyPredicates = rule.bodySubstrings
                    .map { keyword in
                        let escapedKeyword = keyword.replacingOccurrences(of: "'", with: "''")
                        return "COALESCE(\(bodyColumn), '') LIKE '%\(escapedKeyword)%'"
                    }
                    .joined(separator: " OR ")

                if let target = rule.target?.replacingOccurrences(of: "'", with: "''") {
                    return "(target = '\(target)' AND (\(bodyPredicates)))"
                }

                return "(\(bodyPredicates))"
            }
            .joined(separator: " OR ")
    }
}

private final class SQLiteStatement {
    let handle: OpaquePointer
    private let database: OpaquePointer

    init(database: OpaquePointer, sql: String) throws {
        self.database = database

        var handle: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &handle, nil)
        guard prepareResult == SQLITE_OK, let handle else {
            throw CodexThreadRuntimeStore.UnavailableReason.queryFailed(
                message: Self.errorMessage(for: database)
            )
        }

        self.handle = handle
    }

    deinit {
        sqlite3_finalize(self.handle)
    }

    func bindInt64(_ value: Int64, at index: Int32) throws {
        guard sqlite3_bind_int64(self.handle, index, value) == SQLITE_OK else {
            throw CodexThreadRuntimeStore.UnavailableReason.queryFailed(
                message: Self.errorMessage(for: self.database)
            )
        }
    }

    func bindText(_ value: String, at index: Int32) throws {
        guard sqlite3_bind_text(self.handle, index, value, -1, sqliteTransientDestructor) == SQLITE_OK else {
            throw CodexThreadRuntimeStore.UnavailableReason.queryFailed(
                message: Self.errorMessage(for: self.database)
            )
        }
    }

    func bindNullableText(_ value: String?, at index: Int32) throws {
        if let value {
            try self.bindText(value, at: index)
            return
        }

        guard sqlite3_bind_null(self.handle, index) == SQLITE_OK else {
            throw CodexThreadRuntimeStore.UnavailableReason.queryFailed(
                message: Self.errorMessage(for: self.database)
            )
        }
    }

    func text(at column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(self.handle, column) else { return nil }
        return String(cString: pointer)
    }

    func int64(at column: Int32) -> Int64 {
        sqlite3_column_int64(self.handle, column)
    }

    private static func errorMessage(for database: OpaquePointer) -> String {
        guard let pointer = sqlite3_errmsg(database) else { return "sqlite error" }
        return String(cString: pointer)
    }
}
