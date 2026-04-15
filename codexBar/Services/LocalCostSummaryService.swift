import Foundation

struct LocalCostSummaryService {
    private struct SummaryAccumulator {
        var today: Double = 0
        var last30: Double = 0
        var lifetime: Double = 0
        var todayTokens = 0
        var last30Tokens = 0
        var lifetimeTokens = 0
        var daily: [Date: (cost: Double, tokens: Int)] = [:]
        var todayEntries: [TodayCostEntry] = []
        var nextTodayEntryOrdinal = 0
    }

    private struct Pricing {
        let input: Double
        let output: Double
        let cachedInput: Double?
    }

    private let sessionLogStore: SessionLogStore
    private let calendar: Calendar

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

    init(
        sessionLogStore: SessionLogStore = .shared,
        calendar: Calendar = .current
    ) {
        self.sessionLogStore = sessionLogStore
        self.calendar = calendar
    }

    func load(now: Date = Date()) -> LocalCostSummary {
        let todayStart = self.calendar.startOfDay(for: now)
        let last30Start = self.calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart

        let summary = self.sessionLogStore.reduceUsageEvents(into: SummaryAccumulator()) { accumulator, record, event in
            let totalTokens = event.usage.totalTokens
            let resolvedModel = event.model?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? record.model
            let cost = self.costUSD(model: resolvedModel, usage: event.usage)
            let day = self.calendar.startOfDay(for: event.timestamp)

            if event.timestamp >= last30Start {
                if let cost {
                    accumulator.last30 += cost
                }
                accumulator.last30Tokens += totalTokens
            }
            if event.timestamp >= todayStart {
                if let cost {
                    accumulator.today += cost
                }
                accumulator.todayTokens += totalTokens
                accumulator.nextTodayEntryOrdinal += 1
                accumulator.todayEntries.append(
                    self.makeTodayEntry(
                        ordinal: accumulator.nextTodayEntryOrdinal,
                        model: resolvedModel,
                        event: event,
                        costUSD: cost
                    )
                )
            }

            if let cost {
                accumulator.lifetime += cost
            }
            accumulator.lifetimeTokens += totalTokens

            let current = accumulator.daily[day] ?? (0, 0)
            accumulator.daily[day] = (current.cost + (cost ?? 0), current.tokens + totalTokens)
        }

        let dailyEntries = summary.daily.map { date, value in
            DailyCostEntry(
                id: ISO8601DateFormatter().string(from: date),
                date: date,
                costUSD: value.cost,
                totalTokens: value.tokens
            )
        }.sorted { $0.date > $1.date }

        let todayEntries = summary.todayEntries.sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id > rhs.id
            }
            return lhs.timestamp > rhs.timestamp
        }
        let todayChartEntries = self.makeTodayChartEntries(from: todayEntries, now: now)

        return LocalCostSummary(
            todayCostUSD: summary.today,
            todayTokens: summary.todayTokens,
            last30DaysCostUSD: summary.last30,
            last30DaysTokens: summary.last30Tokens,
            lifetimeCostUSD: summary.lifetime,
            lifetimeTokens: summary.lifetimeTokens,
            dailyEntries: dailyEntries,
            todayEntries: todayEntries,
            todayChartEntries: todayChartEntries,
            updatedAt: now
        )
    }

    private func costUSD(model: String?, usage: SessionLogStore.Usage) -> Double? {
        guard let pricing = self.pricing(for: model) else { return nil }
        let cached = min(max(0, usage.cachedInputTokens), max(0, usage.inputTokens))
        let nonCached = max(0, usage.inputTokens - cached)
        return Double(nonCached) * pricing.input +
            Double(cached) * (pricing.cachedInput ?? pricing.input) +
            Double(usage.outputTokens) * pricing.output
    }

    private func pricing(for model: String?) -> Pricing? {
        guard let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines),
              normalizedModel.isEmpty == false else {
            return nil
        }

        if let exact = self.pricingByModel[normalizedModel] {
            return exact
        }

        let lowercased = normalizedModel.lowercased()
        if let exactLowercased = self.pricingByModel[lowercased] {
            return exactLowercased
        }

        let aliasCandidates = [
            lowercased.replacingOccurrences(of: #"-latest$"#, with: "", options: .regularExpression),
            lowercased.replacingOccurrences(of: #"-preview$"#, with: "", options: .regularExpression),
            lowercased.replacingOccurrences(of: #"-\d{4}-\d{2}-\d{2}$"#, with: "", options: .regularExpression),
        ]
        for candidate in aliasCandidates where candidate.isEmpty == false {
            if let pricing = self.pricingByModel[candidate] {
                return pricing
            }
        }

        return nil
    }

    private func makeTodayEntry(
        ordinal: Int,
        model: String,
        event: SessionLogStore.UsageEvent,
        costUSD: Double?
    ) -> TodayCostEntry {
        let requestTokens = max(0, event.usage.inputTokens)
        let cachedRequestTokens = min(max(0, event.usage.cachedInputTokens), requestTokens)
        let responseTokens = max(0, event.usage.outputTokens)

        return TodayCostEntry(
            id: "\(model)-\(Int(event.timestamp.timeIntervalSince1970 * 1000))-\(ordinal)",
            timestamp: event.timestamp,
            model: model,
            costUSD: costUSD ?? 0,
            hasKnownPricing: costUSD != nil,
            requestTokens: requestTokens,
            cachedRequestTokens: cachedRequestTokens,
            responseTokens: responseTokens,
            totalTokens: requestTokens + responseTokens
        )
    }

    private func makeTodayChartEntries(from entries: [TodayCostEntry], now: Date) -> [TodayChartEntry] {
        let dayStart = self.calendar.startOfDay(for: now)
        guard let eightAM = self.calendar.date(byAdding: .hour, value: 8, to: dayStart),
              now > eightAM else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        var chartEntries: [TodayChartEntry] = []
        var bucketStart = eightAM

        while bucketStart < now {
            guard let nextHour = self.calendar.date(byAdding: .hour, value: 1, to: bucketStart) else { break }
            let bucketEnd = min(nextHour, now)
            let bucketEvents = entries.filter { entry in
                entry.timestamp >= bucketStart && entry.timestamp < bucketEnd
            }

            chartEntries.append(
                TodayChartEntry(
                    id: isoFormatter.string(from: bucketStart),
                    startDate: bucketStart,
                    endDate: bucketEnd,
                    costUSD: bucketEvents.reduce(0) { $0 + $1.costUSD },
                    hasKnownPricing: bucketEvents.contains(where: \.hasKnownPricing),
                    totalTokens: bucketEvents.reduce(0) { $0 + $1.totalTokens }
                )
            )

            bucketStart = nextHour
        }

        return chartEntries
    }
}

private extension String {
    var nonEmpty: String? {
        self.isEmpty ? nil : self
    }
}
