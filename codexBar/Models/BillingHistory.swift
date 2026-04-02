import Foundation

struct BillingSessionEntry: Identifiable {
    let id: String
    let startedAt: Date
    let model: String
    let costUSD: Double
    let providerId: String?
    let providerLabel: String
    let accountId: String?
    let accountLabel: String
}

struct BillingBucketSummary: Identifiable {
    let id: String
    let providerId: String?
    let providerLabel: String
    let accountId: String?
    let accountLabel: String
    let todayCostUSD: Double
    let last30DaysCostUSD: Double
    let sessionCount: Int
}

struct BillingHistory {
    var buckets: [BillingBucketSummary]
    var recentSessions: [BillingSessionEntry]
    var updatedAt: Date?

    static let empty = BillingHistory(buckets: [], recentSessions: [], updatedAt: nil)
}

