import Foundation

struct LocalCostSummaryService {
    private struct Pricing {
        let input: Double
        let output: Double
        let cachedInput: Double?
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

    func load(now: Date = Date()) -> LocalCostSummary {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart

        var today: Double = 0
        var last30: Double = 0
        var lifetime: Double = 0
        var lifetimeTokens = 0
        var daily: [Date: (cost: Double, tokens: Int)] = [:]

        for fileURL in self.sessionFiles() {
            guard let record = self.parse(fileURL: fileURL) else { continue }
            let cost = self.costUSD(model: record.model, usage: record.usage)
            guard let cost else { continue }

            let totalTokens = record.usage.inputTokens + record.usage.outputTokens
            let day = calendar.startOfDay(for: record.date)

            if record.date >= last30Start {
                last30 += cost
            }
            if record.date >= todayStart {
                today += cost
            }

            lifetime += cost
            lifetimeTokens += totalTokens

            let current = daily[day] ?? (0, 0)
            daily[day] = (current.cost + cost, current.tokens + totalTokens)
        }

        let dailyEntries = daily.map { date, value in
            DailyCostEntry(
                id: ISO8601DateFormatter().string(from: date),
                date: date,
                costUSD: value.cost,
                totalTokens: value.tokens
            )
        }.sorted { $0.date > $1.date }

        return LocalCostSummary(
            todayCostUSD: today,
            last30DaysCostUSD: last30,
            lifetimeCostUSD: lifetime,
            lifetimeTokens: lifetimeTokens,
            dailyEntries: dailyEntries,
            updatedAt: now
        )
    }

    private func sessionFiles() -> [URL] {
        let fileManager = FileManager.default
        let directories = [
            CodexPaths.codexRoot.appendingPathComponent("sessions", isDirectory: true),
            CodexPaths.codexRoot.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
        var files: [URL] = []
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "jsonl" {
                    files.append(url)
                }
            }
        }
        return files
    }

    private func parse(fileURL: URL) -> (date: Date, model: String, usage: Usage)? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL),
              let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        defer { try? handle.close() }

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

        guard let date = sessionDate, let resolvedModel = model, let usage = latestUsage else { return nil }
        return (date, resolvedModel, usage)
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

    private struct Usage {
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
    }
}
