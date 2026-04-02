import Foundation

struct BillingHistoryService {
    private struct Pricing {
        let input: Double
        let output: Double
        let cachedInput: Double?
    }

    private struct Usage {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
    }

    private struct SessionRecord {
        let id: String
        let startedAt: Date
        let model: String
        let usage: Usage
    }

    private struct ActivationRecord {
        let timestamp: Date
        let providerId: String?
        let accountId: String?
    }

    private struct BucketAccumulator {
        var providerId: String?
        var providerLabel: String
        var accountId: String?
        var accountLabel: String
        var todayCostUSD: Double = 0
        var last30DaysCostUSD: Double = 0
        var sessionCount: Int = 0
    }

    private let pricingByModel: [String: Pricing] = [
        "gpt-5": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5-codex": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5-mini": Pricing(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
        "gpt-5-nano": Pricing(input: 5e-8, output: 4e-7, cachedInput: 5e-9),
        "gpt-5.1": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex-max": Pricing(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex-mini": Pricing(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
        "gpt-5.2": Pricing(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.2-codex": Pricing(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.3-codex": Pricing(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.4": Pricing(input: 2.5e-6, output: 1.5e-5, cachedInput: 2.5e-7),
        "gpt-5.4-mini": Pricing(input: 7.5e-7, output: 4.5e-6, cachedInput: 7.5e-8),
        "gpt-5.4-nano": Pricing(input: 2e-7, output: 1.25e-6, cachedInput: 2e-8),
        "qwen35_4b": Pricing(input: 0, output: 0, cachedInput: 0),
    ]

    func load(config: CodexBarConfig, now: Date = Date()) -> BillingHistory {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart

        let providersByID = Dictionary(uniqueKeysWithValues: config.providers.map { ($0.id, $0) })
        let activations = self.loadActivations()

        var buckets: [String: BucketAccumulator] = [:]
        var recentSessions: [BillingSessionEntry] = []

        for record in self.sessionRecords() {
            guard let costUSD = self.costUSD(model: record.model, usage: record.usage) else { continue }
            let attribution = self.resolveAttribution(for: record.startedAt, activations: activations, providersByID: providersByID)
            let bucketKey = (attribution.providerId ?? "unattributed") + "::" + (attribution.accountId ?? "unattributed")

            var bucket = buckets[bucketKey] ?? BucketAccumulator(
                providerId: attribution.providerId,
                providerLabel: attribution.providerLabel,
                accountId: attribution.accountId,
                accountLabel: attribution.accountLabel
            )

            if record.startedAt >= todayStart {
                bucket.todayCostUSD += costUSD
            }
            if record.startedAt >= last30Start {
                bucket.last30DaysCostUSD += costUSD
            }
            bucket.sessionCount += 1
            buckets[bucketKey] = bucket

            recentSessions.append(
                BillingSessionEntry(
                    id: "\(record.id)-\(Int(record.startedAt.timeIntervalSince1970))",
                    startedAt: record.startedAt,
                    model: record.model,
                    costUSD: costUSD,
                    providerId: attribution.providerId,
                    providerLabel: attribution.providerLabel,
                    accountId: attribution.accountId,
                    accountLabel: attribution.accountLabel
                )
            )
        }

        let summaries = buckets.values.map { bucket in
            BillingBucketSummary(
                id: (bucket.providerId ?? "unattributed") + "::" + (bucket.accountId ?? "unattributed"),
                providerId: bucket.providerId,
                providerLabel: bucket.providerLabel,
                accountId: bucket.accountId,
                accountLabel: bucket.accountLabel,
                todayCostUSD: bucket.todayCostUSD,
                last30DaysCostUSD: bucket.last30DaysCostUSD,
                sessionCount: bucket.sessionCount
            )
        }.sorted {
            if $0.last30DaysCostUSD != $1.last30DaysCostUSD {
                return $0.last30DaysCostUSD > $1.last30DaysCostUSD
            }
            return $0.providerLabel < $1.providerLabel
        }

        let recent = recentSessions.sorted { $0.startedAt > $1.startedAt }

        return BillingHistory(
            buckets: summaries,
            recentSessions: Array(recent.prefix(10)),
            updatedAt: now
        )
    }

    private func sessionRecords() -> [SessionRecord] {
        let fileManager = FileManager.default
        let directories = [
            CodexPaths.codexRoot.appendingPathComponent("sessions", isDirectory: true),
            CodexPaths.codexRoot.appendingPathComponent("archived_sessions", isDirectory: true),
        ]

        var records: [SessionRecord] = []
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "jsonl", let record = self.parseSession(url) else { continue }
                records.append(record)
            }
        }
        return records
    }

    private func parseSession(_ fileURL: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var sessionID: String?
        var sessionDate: Date?
        var model: String?
        var latestUsage: Usage?

        for line in text.split(separator: "\n") {
            guard let jsonData = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else { continue }

            switch type {
            case "session_meta":
                sessionID = payload["id"] as? String
                if let timestamp = payload["timestamp"] as? String {
                    sessionDate = ISO8601Parsing.parse(timestamp)
                }
            case "turn_context":
                if let currentModel = payload["model"] as? String {
                    model = self.normalizeModel(currentModel)
                }
            case "event_msg":
                guard let payloadType = payload["type"] as? String, payloadType == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let total = info["total_token_usage"] as? [String: Any] else { continue }
                latestUsage = Usage(
                    inputTokens: total["input_tokens"] as? Int ?? 0,
                    cachedInputTokens: total["cached_input_tokens"] as? Int ?? 0,
                    outputTokens: total["output_tokens"] as? Int ?? 0
                )
            default:
                continue
            }
        }

        guard let id = sessionID ?? fileURL.deletingPathExtension().lastPathComponent as String?,
              let startedAt = sessionDate,
              let model,
              let latestUsage else { return nil }

        return SessionRecord(id: id, startedAt: startedAt, model: model, usage: latestUsage)
    }

    private func loadActivations() -> [ActivationRecord] {
        guard let text = try? String(contentsOf: CodexPaths.switchJournalURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestampString = json["timestamp"] as? String,
                  let timestamp = ISO8601Parsing.parse(timestampString) else { return nil }
            return ActivationRecord(
                timestamp: timestamp,
                providerId: json["providerId"] as? String,
                accountId: json["accountId"] as? String
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    private func resolveAttribution(
        for sessionDate: Date,
        activations: [ActivationRecord],
        providersByID: [String: CodexBarProvider]
    ) -> (providerId: String?, providerLabel: String, accountId: String?, accountLabel: String) {
        guard let activation = activations.last(where: { $0.timestamp <= sessionDate }),
              let providerId = activation.providerId,
              let provider = providersByID[providerId] else {
            return (nil, "Unattributed", nil, "Unknown")
        }

        let account = provider.accounts.first(where: { $0.id == activation.accountId })
        return (
            providerId,
            provider.label,
            account?.id,
            account?.label ?? "Unknown"
        )
    }

    private func normalizeModel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            return String(trimmed.dropFirst("openai/".count))
        }
        return trimmed
    }

    private func costUSD(model: String, usage: Usage) -> Double? {
        guard let pricing = self.pricingByModel[model] else { return nil }
        let cached = min(max(0, usage.cachedInputTokens), max(0, usage.inputTokens))
        let nonCached = max(0, usage.inputTokens - cached)
        return Double(nonCached) * pricing.input +
            Double(cached) * (pricing.cachedInput ?? pricing.input) +
            Double(usage.outputTokens) * pricing.output
    }
}
