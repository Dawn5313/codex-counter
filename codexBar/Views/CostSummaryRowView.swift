import SwiftUI

struct CostSummaryRowView: View {
    let summary: LocalCostSummary
    let currency: (Double) -> String
    let compactTokens: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L.costTitle)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            Text(L.costTodaySummary(currency(summary.todayCostUSD), compactTokens(summary.todayTokens)))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text(L.costLast30Summary(currency(summary.last30DaysCostUSD), compactTokens(summary.last30DaysTokens)))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

struct CostDetailsPanelView: View {
    static let panelWidth: CGFloat = 408

    private static let detailRowHeight: CGFloat = 28
    private static let detailMaxVisibleRows = 5
    private static let detailTimeColumnWidth: CGFloat = 58
    private static let detailTokenColumnWidth: CGFloat = 50
    private static let detailCostColumnWidth: CGFloat = 72

    static func panelHeight(summary: LocalCostSummary) -> CGFloat {
        let baseHeight: CGFloat = summary.todayChartEntries.isEmpty ? 184 : 336
        let todayEntryCount = summary.todayEntries.count
        guard todayEntryCount > 0 else { return baseHeight }

        let visibleRows = min(todayEntryCount, Self.detailMaxVisibleRows)
        let detailSectionHeight = CGFloat(visibleRows) * Self.detailRowHeight + 76
        return min(560, baseHeight + detailSectionHeight)
    }

    private struct Point: Identifiable {
        let id: String
        let startDate: Date
        let endDate: Date
        let costUSD: Double
        let hasKnownPricing: Bool
        let totalTokens: Int
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("HH:mm:ss")
        return formatter
    }()

    private static let detailNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = Locale.autoupdatingCurrent.groupingSeparator
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    private static let detailCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    private static let chartAxisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter
    }()

    private struct MiniBarChart: View {
        let points: [Point]
        @Binding var selectedID: String?

        private let minBarHeight: CGFloat = 6
        private let barSpacing: CGFloat = 4

        var body: some View {
            GeometryReader { geometry in
                let maxCost = max(points.map(\.costUSD).max() ?? 0, 0.01)
                let slotWidth = geometry.size.width / CGFloat(Swift.max(points.count, 1))

                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(points) { point in
                        let isSelected = selectedID == point.id
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.68))
                            .frame(maxWidth: .infinity)
                            .frame(height: self.barHeight(for: point, totalHeight: geometry.size.height, maxCost: maxCost))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard points.isEmpty == false,
                              location.x >= 0,
                              location.x <= geometry.size.width else {
                            selectedID = nil
                            return
                        }

                        let index = min(max(Int(location.x / max(slotWidth, 1)), 0), points.count - 1)
                        selectedID = points[index].id
                    case .ended:
                        selectedID = nil
                    }
                }
            }
            .frame(height: 128)
        }

        private func barHeight(for point: Point, totalHeight: CGFloat, maxCost: Double) -> CGFloat {
            guard totalHeight > 0 else { return minBarHeight }
            let usableHeight = max(totalHeight - 4, minBarHeight)
            let ratio = point.costUSD > 0 ? CGFloat(point.costUSD / maxCost) : 0
            return max(minBarHeight, usableHeight * ratio)
        }
    }

    let summary: LocalCostSummary
    let currency: (Double) -> String
    let compactTokens: (Int) -> String
    let shortDay: (Date) -> String

    @State private var selectedID: String?

    private var points: [Point] {
        summary.todayChartEntries.map { entry in
            Point(
                id: entry.id,
                startDate: entry.startDate,
                endDate: entry.endDate,
                costUSD: entry.costUSD,
                hasKnownPricing: entry.hasKnownPricing,
                totalTokens: entry.totalTokens
            )
        }
    }

    private var chartStartLabel: String? {
        points.first.map { Self.chartAxisFormatter.string(from: $0.startDate) }
    }

    private var chartEndLabel: String? {
        points.last.map { Self.chartAxisFormatter.string(from: $0.endDate) }
    }

    private var hasChartData: Bool {
        points.isEmpty == false
    }

    private func chartRangeLabel(for point: Point) -> String {
        let start = Self.chartAxisFormatter.string(from: point.startDate)
        let end = Self.chartAxisFormatter.string(from: point.endDate)
        return "\(start) - \(end)"
    }

    private var chartPrimaryLabel: String {
        if let point = selectedPoint {
            if point.hasKnownPricing == false && point.totalTokens > 0 {
                return "\(chartRangeLabel(for: point)) · \(L.costUnavailable)"
            }
            return "\(chartRangeLabel(for: point)) · \(currency(point.costUSD))"
        }
        return L.costTodayTrendTitle
    }

    private var chartSecondaryLabel: String {
        if let point = selectedPoint {
            return L.tokenCount(compactTokens(point.totalTokens))
        }
        return L.costTodayTrendHint
    }

    private var chartEmptyLabel: String {
        if summary.todayEntries.isEmpty {
            return L.costNoHistory
        }
        return L.costTodayTrendEmpty
    }

    private var hasTodayDetails: Bool {
        summary.todayEntries.isEmpty == false
    }

    private var detailTableHeight: CGFloat {
        CGFloat(min(summary.todayEntries.count, Self.detailMaxVisibleRows)) * Self.detailRowHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metricRow(title: L.costMetricToday, cost: summary.todayCostUSD, tokens: summary.todayTokens)
            metricRow(title: L.costMetricLast30Days, cost: summary.last30DaysCostUSD, tokens: summary.last30DaysTokens)
            metricRow(title: L.costMetricAllTime, cost: summary.lifetimeCostUSD, tokens: summary.lifetimeTokens)

            Divider()

            if hasChartData {
                MiniBarChart(points: points, selectedID: $selectedID)

                HStack {
                    if let chartStartLabel {
                        Text(chartStartLabel)
                    }

                    Spacer()

                    if let chartEndLabel {
                        Text(chartEndLabel)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(chartPrimaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                    Text(chartSecondaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                }
            } else {
                Text(chartEmptyLabel)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if hasTodayDetails {
                Divider()
                todayDetailsSection
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(
            width: Self.panelWidth,
            height: Self.panelHeight(summary: summary),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var selectedPoint: Point? {
        guard let selectedID else { return nil }
        return points.first(where: { $0.id == selectedID })
    }

    private func metricRow(title: String, cost: Double, tokens: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(L.tokenCount(compactTokens(tokens)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(currency(cost))
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private var todayDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.costTodayDetailsTitle)
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text(L.costTodayDetailsCount(summary.todayEntries.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            detailHeaderRow

            ScrollView(.vertical, showsIndicators: summary.todayEntries.count > Self.detailMaxVisibleRows) {
                LazyVStack(spacing: 6) {
                    ForEach(summary.todayEntries) { entry in
                        detailRow(entry)
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: detailTableHeight)
        }
    }

    private var detailHeaderRow: some View {
        HStack(spacing: 6) {
            detailHeaderCell(L.costDetailsTime, width: Self.detailTimeColumnWidth, alignment: .leading)
            detailHeaderCell(L.costDetailsRequest, width: Self.detailTokenColumnWidth)
            detailHeaderCell(L.costDetailsCached, width: Self.detailTokenColumnWidth)
            detailHeaderCell(L.costDetailsResponse, width: Self.detailTokenColumnWidth)
            detailHeaderCell(L.costDetailsTotal, width: Self.detailTokenColumnWidth)
            detailHeaderCell(L.costDetailsCost, width: Self.detailCostColumnWidth)
        }
    }

    private func detailHeaderCell(_ title: String, width: CGFloat, alignment: Alignment = .trailing) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
    }

    private func detailRow(_ entry: TodayCostEntry) -> some View {
        HStack(spacing: 6) {
            detailValueCell(Self.timeFormatter.string(from: entry.timestamp), width: Self.detailTimeColumnWidth, alignment: .leading)
            detailValueCell(detailTokenCount(entry.requestTokens), width: Self.detailTokenColumnWidth)
            detailValueCell(detailTokenCount(entry.cachedRequestTokens), width: Self.detailTokenColumnWidth)
            detailValueCell(detailTokenCount(entry.responseTokens), width: Self.detailTokenColumnWidth)
            detailValueCell(detailTokenCount(entry.totalTokens), width: Self.detailTokenColumnWidth)
            detailValueCell(detailCost(entry), width: Self.detailCostColumnWidth)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.detailRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
        .help("\(entry.model) · \(entry.hasKnownPricing ? currency(entry.costUSD) : L.costUnavailable)")
    }

    private func detailValueCell(_ value: String, width: CGFloat, alignment: Alignment = .trailing) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: alignment)
    }

    private func detailTokenCount(_ value: Int) -> String {
        Self.detailNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func detailCost(_ entry: TodayCostEntry) -> String {
        let value = entry.costUSD
        guard entry.hasKnownPricing else { return L.costUnavailable }
        if value >= 0.01 {
            return currency(value)
        }
        return Self.detailCurrencyFormatter.string(from: NSNumber(value: value)) ?? currency(value)
    }
}
