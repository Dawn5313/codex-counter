import Foundation

struct DailyCostEntry: Identifiable {
    let id: String
    let date: Date
    let costUSD: Double
    let totalTokens: Int
}

struct LocalCostSummary {
    var todayCostUSD: Double
    var last30DaysCostUSD: Double
    var lifetimeCostUSD: Double
    var lifetimeTokens: Int
    var dailyEntries: [DailyCostEntry]
    var updatedAt: Date?

    static let empty = LocalCostSummary(
        todayCostUSD: 0,
        last30DaysCostUSD: 0,
        lifetimeCostUSD: 0,
        lifetimeTokens: 0,
        dailyEntries: [],
        updatedAt: nil
    )
}
