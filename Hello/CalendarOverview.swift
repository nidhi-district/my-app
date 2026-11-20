import SwiftUI

enum CalendarTab: String, CaseIterable, Identifiable {
    case day, week, year

    var id: Self { self }

    var symbol: String {
        switch self {
        case .day: "note.text"
        case .week: "calendar"
        case .year: "calendar.day.timeline.left"
        }
    }
}

enum CalendarScrollActivity: Equatable {
    case idle, tracking, fingerUp, fingerDown
}

struct CalendarTabBar: View {
    let selection: CalendarTab
    let isCompact: Bool
    let tabHeight: CGFloat
    let select: (CalendarTab) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .caption) private var labelHeight = Size.tabLabelHeight
    @Namespace private var selectionMotion

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(CalendarTab.allCases) { tab in
                let active = tab == selection
                Button {
                    select(tab)
                } label: {
                    VStack(spacing: isCompact ? 0 : Space.xxs) {
                        Image(systemName: tab.symbol)
                            .font(Typeface.tabIcon)
                            .accessibilityHidden(true)
                        Text(tab.rawValue)
                            .font(tab == .year ? Typeface.yearTabLabel : Typeface.tabLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(height: isCompact ? 0 : labelHeight)
                            .clipped()
                            .opacity(isCompact ? 0 : 1)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(active ? Ink.text : Ink.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: isCompact ? Size.tapTarget : tabHeight)
                    .background {
                        if active { selectionIndicator }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityIdentifier("tab-\(tab.rawValue)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(Space.xxs)
        .frame(width: isCompact ? Size.compactTabBarWidth : Size.tabBarWidth)
        .glass(Capsule(), untinted: true)
        // Keep the backdrop and baselines still as the glass capsule shrinks.
        .frame(height: tabHeight + Space.xs, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.xxs)
        .background {
            LinearGradient(stops: [
                .init(color: Ink.canvas.opacity(0), location: 0),
                .init(color: Ink.canvas.opacity(0.14), location: 0.38),
                .init(color: Ink.canvas.opacity(0.48), location: 0.72),
                .init(color: Ink.canvas.opacity(0.88), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .opacity(isCompact ? 0.78 : 1)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var selectionIndicator: some View {
        if reduceMotion {
            selectionLens
        } else {
            selectionLens.matchedGeometryEffect(id: "selected-tab", in: selectionMotion)
        }
    }

    @ViewBuilder private var selectionLens: some View {
        if reduceTransparency {
            Capsule().fill(Ink.text.opacity(0.10))
        } else {
            Capsule()
                .fill(PaperGlassColor.lensReflection)
                .overlay { Capsule().strokeBorder(PaperGlassColor.lensRim) }
        }
    }
}

struct WeekOverview: View {
    let date: Date
    @Binding var period: Date
    let stickersForDate: (Date) -> [PlacedSticker]
    let openDay: (Date) -> Void
    let onScrollActivity: (CalendarScrollActivity) -> Void
    @Environment(\.calendar) private var calendar

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: period)?.start ?? period
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let days = days
        VStack(spacing: Space.md) {
            CalendarPeriodHeader(title: rangeLabel(days), unit: "week") { offset in
                period = calendar.date(byAdding: .weekOfYear, value: offset, to: period) ?? period
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: Space.xs) {
                    ForEach(days, id: \.self) { day in
                        let focused = calendar.isDate(day, inSameDayAs: date)
                        let stickers = stickersForDate(day).filter { $0.asset != nil }
                        Button {
                            openDay(day)
                        } label: {
                            HStack(spacing: Space.sm) {
                                CalendarNoteThumbnail(date: day, stickers: stickers, active: focused)
                                    .frame(width: Size.tapTarget, height: Size.tapTarget)
                                    .accessibilityHidden(true)
                                Text(day.formatted(.dateTime.weekday(.wide)))
                                    .font(Typeface.body)
                                Spacer(minLength: Space.xs)
                                if calendar.isDateInToday(day) {
                                    Text("today")
                                        .font(Typeface.caption)
                                        .foregroundStyle(Ink.muted)
                                }
                                Image(systemName: "chevron.forward")
                                    .font(Typeface.iconSmall)
                                    .foregroundStyle(Ink.muted)
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(Ink.text)
                            .padding(.horizontal, Space.md)
                            .padding(.vertical, Space.xs)
                            .frame(minHeight: Size.weekRow)
                            .background(focused ? CraftTint.butter.fill : .white,
                                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Ink.hairline) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .accessibilityValue(stickerCountLabel(stickers))
                        .accessibilityAddTraits(focused ? .isSelected : [])
                        .accessibilityIdentifier("week-day-\(StickerStorage.dayKey(for: day))")
                    }
                }
                .padding(.bottom, Space.sm)
            }
            .onCalendarScrollActivity(onScrollActivity)
        }
        .padding(.horizontal, Space.margin)
    }

    private func rangeLabel(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.dateTemplate = "d MMM"
        return formatter.string(from: first, to: last)
    }
}

struct YearOverview: View {
    let date: Date
    @Binding var period: Date
    let stickersForDate: (Date) -> [PlacedSticker]
    let openDay: (Date) -> Void
    let onScrollActivity: (CalendarScrollActivity) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleMonth: Date?
    @State private var restingScrollOffset: CGFloat?
    @State private var hasScrollUnderlap = false

    private var showsHeaderBlur: Bool { hasScrollUnderlap && !reduceTransparency }

    /// Keep the adjacent months in the scroll so the grid continues at year boundaries.
    private var months: [Date] {
        guard let year = calendar.dateInterval(of: .year, for: period),
              let range = calendar.range(of: .month, in: .year, for: period) else { return [] }
        return (-1...range.count).compactMap { calendar.date(byAdding: .month, value: $0, to: year.start) }
    }

    var body: some View {
        VStack(spacing: 0) {
            periodHeader
                .background { headerBackdrop }
                .zIndex(1)
            if #available(iOS 26.0, *) {
                monthScroll
                    .safeAreaBar(edge: .top, spacing: 0) {
                        Color.clear.frame(height: Space.xs)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .scrollEdgeEffectHidden(true, for: .top)
            } else {
                monthScroll
            }
        }
    }

    private var headerBackdrop: some View {
        ZStack {
            if showsHeaderBlur {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                    .mask {
                        VStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                                .frame(height: Space.md)
                        }
                    }
                    .overlay(alignment: .top) {
                        // Blend into the status area while keeping the calendar blurred at the top edge.
                        LinearGradient(colors: [Ink.canvas, Ink.canvas.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: Space.sm)
                    }
            } else {
                Ink.canvas
            }
        }
        .allowsHitTesting(false)
    }

    private var periodHeader: some View {
        CalendarPeriodHeader(title: (visibleMonth ?? period).formatted(.dateTime.month(.wide).year()),
                             unit: "year", font: Typeface.yearHeading, step: stepYear)
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.md)
    }

    private var monthScroll: some View {
        ScrollViewReader { scroll in
            observedMonthGrid
                .task(id: monthStart(for: period)) {
                    let activeMonth = monthStart(for: period)
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { scroll.scrollTo(activeMonth, anchor: .top) }
                }
        }
        .id(calendar.dateInterval(of: .year, for: period)?.start)
    }

    private var observedMonthGrid: some View {
        monthGrid.onCalendarScrollActivity(onScrollActivity, onTouch: { offset in
            // Year opens partway through the scroll. Use the offset before the first user drag.
            if restingScrollOffset == nil { restingScrollOffset = offset }
        }, onOffset: { offset in
            guard let restingScrollOffset else { return }
            let hasUnderlap = abs(offset - restingScrollOffset) > Space.xxs
            guard hasUnderlap != hasScrollUnderlap else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                hasScrollUnderlap = hasUnderlap
            }
        })
    }

    private var monthGrid: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: Space.xxl) {
                ForEach(months, id: \.self) { start in
                    MonthNoteGrid(start: start, selected: date, calendar: calendar,
                                  stickersForDate: stickersForDate, openDay: openDay)
                        .id(start)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.lg)
        }
        // Let paper pass beneath the backdrop while keeping the scroll's touch bounds below the header.
        .scrollClipDisabled()
        .scrollPosition(id: $visibleMonth, anchor: .top)
        .accessibilityIdentifier("month-scroll")
    }

    private func stepYear(_ offset: Int) {
        guard let next = calendar.date(byAdding: .year, value: offset, to: visibleMonth ?? period) else { return }
        restingScrollOffset = nil
        hasScrollUnderlap = false
        visibleMonth = nil
        period = next
    }

    private func monthStart(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

extension View {
    func onCalendarScrollActivity(_ onActivity: @escaping (CalendarScrollActivity) -> Void,
                                  onTouch: ((CGFloat) -> Void)? = nil,
                                  onOffset: ((CGFloat) -> Void)? = nil) -> some View {
        modifier(CalendarScrollObserver(onActivity: onActivity, onTouch: onTouch, onOffset: onOffset))
    }

    @ViewBuilder func usesCalendarBottomFade() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            self
        }
    }
}

private struct CalendarScrollObserver: ViewModifier {
    let onActivity: (CalendarScrollActivity) -> Void
    let onTouch: ((CGFloat) -> Void)?
    let onOffset: ((CGFloat) -> Void)?
    @State private var gesture = GestureSample()

    /// Per-pixel samples should only update the view when the reported direction changes.
    private final class GestureSample {
        var anchor: CGFloat?
        var activity = CalendarScrollActivity.idle
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase, context in
                    switch phase {
                    case .tracking, .interacting:
                        let offset = context.geometry.contentOffset.y
                        onTouch?(offset)
                        gesture.anchor = phase == .interacting ? offset : nil
                        report(.tracking)
                    case .idle:
                        gesture.anchor = nil
                        report(.idle)
                    default:
                        // Momentum and programmatic date jumps should never reverse the bar.
                        gesture.anchor = nil
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    onOffset?(offset)
                    guard let anchor = gesture.anchor, abs(offset - anchor) >= Space.xxs / 2 else { return }
                    gesture.anchor = offset
                    report(offset > anchor ? .fingerUp : .fingerDown)
                }
        } else {
            content
        }
    }

    private func report(_ activity: CalendarScrollActivity) {
        guard activity != gesture.activity else { return }
        gesture.activity = activity
        onActivity(activity)
    }
}

private struct MonthNoteGrid: View {
    let start: Date
    let selected: Date
    let calendar: Calendar
    let stickersForDate: (Date) -> [PlacedSticker]
    let openDay: (Date) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private var slots: [Date?] {
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start) }
        let trailing = (7 - (leading + count) % 7) % 7
        return Array(repeating: nil, count: leading) + days + Array(repeating: nil, count: trailing)
    }

    private var weekdays: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    var body: some View {
        let slots = slots
        let weekdays = weekdays
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 0) {
                Text(start.formatted(.dateTime.year()))
                    .font(Typeface.yearCaption)
                    .foregroundStyle(Ink.muted)
                    .accessibilityHidden(true)
                Text(start.formatted(.dateTime.month(.wide)))
                    .font(Typeface.monthTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(start.formatted(.dateTime.month(.wide).year()))
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.leading, Space.xxs)

            VStack(spacing: Space.xs) {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(weekdays.indices, id: \.self) { index in
                        Text(weekdays[index])
                            .font(Typeface.tabLabel)
                            .foregroundStyle(Ink.muted)
                    }
                }
                .accessibilityHidden(true)

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(slots.indices, id: \.self) { index in
                        if let day = slots[index] { dayButton(day) } else { cell.accessibilityHidden(true) }
                    }
                }
            }
        }
    }

    private var cell: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { Rectangle().strokeBorder(Ink.hairline, lineWidth: 0.5).allowsHitTesting(false) }
    }

    private func dayButton(_ day: Date) -> some View {
        let active = calendar.isDate(day, inSameDayAs: selected)
        let stickers = stickersForDate(day).filter { $0.asset != nil }
        return Button {
            openDay(day)
        } label: {
            cell
                .overlay {
                    CalendarNoteThumbnail(date: day, stickers: stickers, active: active)
                        .padding(Space.xxs)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(stickerCountLabel(stickers))
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("month-day-\(StickerStorage.dayKey(for: day))")
    }
}

private func stickerCountLabel(_ stickers: [PlacedSticker]) -> String {
    switch stickers.count {
    case 0: ""
    case 1: "1 sticker"
    default: "\(stickers.count) stickers"
    }
}

private struct CalendarNoteThumbnail: View {
    let date: Date
    let stickers: [PlacedSticker]
    let active: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            let shape = RoundedRectangle(cornerRadius: Space.xxs, style: .continuous)
            shape
                .fill(active ? CraftTint.butter.fill : PadColor.calendarPaper)
                .overlay {
                    Image("PaperTextureSmall")
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: proxy.size.height)
                        .blendMode(.multiply)
                        .opacity(0.42)
                }
                .overlay {
                    VStack(spacing: 0) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(Typeface.paperLabel(side * 0.17))
                            .foregroundStyle(Ink.muted)
                        Text(date.formatted(.dateTime.day()))
                            .font(Typeface.numeral(size: side * 0.57))
                            .foregroundStyle(Ink.text)
                    }
                    .lineLimit(1)
                }
                .overlay {
                    if !stickers.isEmpty {
                        PlacedStickerLayer(stickers: stickers, scalesToCanvas: true)
                    }
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(active ? CraftTint.butter.ink : Ink.hairline)
                }
                .shadow(color: Ink.text.opacity(0.08), radius: Space.xxs, y: Space.xxs / 2)
        }
    }
}

private struct CalendarPeriodHeader: View {
    let title: String
    let unit: String
    var font = Typeface.calendarTitle
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            GlassIcon(symbol: "chevron.left", label: "previous \(unit)") { step(-1) }
            Text(title)
                .font(font)
                .foregroundStyle(Ink.text)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("\(unit)-period")
            GlassIcon(symbol: "chevron.right", label: "next \(unit)") { step(1) }
        }
        .padding(.top, Space.xs)
    }
}
