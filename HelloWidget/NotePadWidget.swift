import SwiftUI
import WidgetKit

/// Home-screen widget: today's date on the same ring-bound paper pad as the app.
@main
struct HelloWidgetBundle: WidgetBundle {
    init() { Typeface.registerBundledFonts() }

    var body: some Widget {
        NotePadWidget()
    }
}

struct NotePadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StickerStorage.widgetKind, provider: DayProvider()) { entry in
            NotePadWidgetView(entry: entry)
                .textCase(.lowercase)
        }
        .configurationDisplayName("Note Pad")
        .description("Today, on a ring-bound pad of paper.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    let date: Date
    var stickers: [PlacedSticker] = []
}

/// One entry per day; the widget turns its page at midnight.
struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let now = Date.now
        let page = StickerStorage.load(forWidget: true)[StickerStorage.dayKey(for: now)] ?? []
        completion(DayEntry(date: now, stickers: page))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let cal = Calendar.current
        let now = Date.now
        let today = cal.startOfDay(for: now)
        let pages = StickerStorage.load(forWidget: true)
        let dates = [now] + (1...7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        let entries = dates.map { date in
            DayEntry(date: date, stickers: pages[StickerStorage.dayKey(for: date)] ?? [])
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - View

struct NotePadWidgetView: View {
    var entry: DayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GeometryReader { geo in
            WidgetPad(date: entry.date, family: family, bounds: geo.size, stickers: entry.stickers)
        }
        .containerBackground(for: .widget) { Ink.canvas }
    }
}

struct NotePadWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NotePadWidgetView(entry: DayEntry(date: .now))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            NotePadWidgetView(entry: DayEntry(date: .now))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            NotePadWidgetView(entry: DayEntry(date: .now))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
        }
    }
}
