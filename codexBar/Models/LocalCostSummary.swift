import Foundation

struct DailyCostEntry: Identifiable, Codable {
    let id: String
    let date: Date
    let costUSD: Double
    let totalTokens: Int
}

struct TodayCostEntry: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let model: String
    let costUSD: Double
    let hasKnownPricing: Bool
    let requestTokens: Int
    let cachedRequestTokens: Int
    let responseTokens: Int
    let totalTokens: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case model
        case costUSD
        case hasKnownPricing
        case requestTokens
        case cachedRequestTokens
        case responseTokens
        case totalTokens
    }

    init(
        id: String,
        timestamp: Date,
        model: String,
        costUSD: Double,
        hasKnownPricing: Bool,
        requestTokens: Int,
        cachedRequestTokens: Int,
        responseTokens: Int,
        totalTokens: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.model = model
        self.costUSD = costUSD
        self.hasKnownPricing = hasKnownPricing
        self.requestTokens = requestTokens
        self.cachedRequestTokens = cachedRequestTokens
        self.responseTokens = responseTokens
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.model = try container.decode(String.self, forKey: .model)
        self.costUSD = try container.decode(Double.self, forKey: .costUSD)
        self.hasKnownPricing = try container.decodeIfPresent(Bool.self, forKey: .hasKnownPricing) ?? true
        self.requestTokens = try container.decode(Int.self, forKey: .requestTokens)
        self.cachedRequestTokens = try container.decode(Int.self, forKey: .cachedRequestTokens)
        self.responseTokens = try container.decode(Int.self, forKey: .responseTokens)
        self.totalTokens = try container.decode(Int.self, forKey: .totalTokens)
    }
}

struct TodayChartEntry: Identifiable, Codable {
    let id: String
    let startDate: Date
    let endDate: Date
    let costUSD: Double
    let hasKnownPricing: Bool
    let totalTokens: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case startDate
        case endDate
        case costUSD
        case hasKnownPricing
        case totalTokens
    }

    init(
        id: String,
        startDate: Date,
        endDate: Date,
        costUSD: Double,
        hasKnownPricing: Bool,
        totalTokens: Int
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.costUSD = costUSD
        self.hasKnownPricing = hasKnownPricing
        self.totalTokens = totalTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.costUSD = try container.decode(Double.self, forKey: .costUSD)
        self.hasKnownPricing = try container.decodeIfPresent(Bool.self, forKey: .hasKnownPricing) ?? true
        self.totalTokens = try container.decode(Int.self, forKey: .totalTokens)
    }
}

struct LocalCostSummary: Codable {
    var todayCostUSD: Double
    var todayTokens: Int
    var last30DaysCostUSD: Double
    var last30DaysTokens: Int
    var lifetimeCostUSD: Double
    var lifetimeTokens: Int
    var dailyEntries: [DailyCostEntry]
    var todayEntries: [TodayCostEntry]
    var todayChartEntries: [TodayChartEntry]
    var updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case todayCostUSD
        case todayTokens
        case last30DaysCostUSD
        case last30DaysTokens
        case lifetimeCostUSD
        case lifetimeTokens
        case dailyEntries
        case todayEntries
        case todayChartEntries
        case updatedAt
    }

    init(
        todayCostUSD: Double,
        todayTokens: Int,
        last30DaysCostUSD: Double,
        last30DaysTokens: Int,
        lifetimeCostUSD: Double,
        lifetimeTokens: Int,
        dailyEntries: [DailyCostEntry],
        todayEntries: [TodayCostEntry],
        todayChartEntries: [TodayChartEntry],
        updatedAt: Date?
    ) {
        self.todayCostUSD = todayCostUSD
        self.todayTokens = todayTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.last30DaysTokens = last30DaysTokens
        self.lifetimeCostUSD = lifetimeCostUSD
        self.lifetimeTokens = lifetimeTokens
        self.dailyEntries = dailyEntries
        self.todayEntries = todayEntries
        self.todayChartEntries = todayChartEntries
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.todayCostUSD = try container.decode(Double.self, forKey: .todayCostUSD)
        self.todayTokens = try container.decode(Int.self, forKey: .todayTokens)
        self.last30DaysCostUSD = try container.decode(Double.self, forKey: .last30DaysCostUSD)
        self.last30DaysTokens = try container.decode(Int.self, forKey: .last30DaysTokens)
        self.lifetimeCostUSD = try container.decode(Double.self, forKey: .lifetimeCostUSD)
        self.lifetimeTokens = try container.decode(Int.self, forKey: .lifetimeTokens)
        self.dailyEntries = try container.decode([DailyCostEntry].self, forKey: .dailyEntries)
        self.todayEntries = try container.decodeIfPresent([TodayCostEntry].self, forKey: .todayEntries) ?? []
        self.todayChartEntries = try container.decodeIfPresent([TodayChartEntry].self, forKey: .todayChartEntries) ?? []
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    static let empty = LocalCostSummary(
        todayCostUSD: 0,
        todayTokens: 0,
        last30DaysCostUSD: 0,
        last30DaysTokens: 0,
        lifetimeCostUSD: 0,
        lifetimeTokens: 0,
        dailyEntries: [],
        todayEntries: [],
        todayChartEntries: [],
        updatedAt: nil
    )
}
