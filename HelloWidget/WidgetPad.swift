import SwiftUI
import WidgetKit

// Shared with the app so the widget can be previewed in-app (launch with -widgets).

/// Today's sheet, edge to edge in the widget. Just the one day, no stack.
struct WidgetPad: View {
    var date: Date
    var family: WidgetFamily
    var bounds: CGSize
    var stickers: [PlacedSticker] = []

    var body: some View {
        WidgetPaper()
            .overlay { DateInk(date: date, family: family) }
            .frame(width: bounds.width, height: bounds.height)
            .overlay { PlacedStickerLayer(stickers: stickers, scalesToCanvas: true) }
            .clipped()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("widget-note")
            .accessibilityValue(stickers.compactMap { $0.asset?.name }.joined(separator: ", "))
    }
}

/// Textured paper, brightened toward white (a smaller texture to stay inside widget memory limits).
private struct WidgetPaper: View {
    var body: some View {
        Color.white
            .overlay {
                Image("PaperTextureSmall")
                    .resizable()
                    .scaledToFill()
            }
            .overlay(Color.white.opacity(0.45))
            .clipped()
    }
}

/// The date written on the sheet: handwritten month and weekday around a big printed numeral.
private struct DateInk: View {
    var date: Date
    var family: WidgetFamily

    private var month: String { date.formatted(.dateTime.month(.wide)).lowercased() }
    private var weekday: String { date.formatted(.dateTime.weekday(.wide)).lowercased() }
    private var day: String { date.formatted(.dateTime.day()) }

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: Space.lg) {
                Text(day)
                    .font(Typeface.numeral(size: 96))
                    .foregroundStyle(Ink.text.opacity(0.88))
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(weekday)
                        .font(Typeface.paperLabel(20))
                        .foregroundStyle(Ink.text.opacity(0.78))
                    Text(month)
                        .font(Typeface.paperLabel(15))
                        .foregroundStyle(Ink.text.opacity(0.6))
                }
            }

        case .systemLarge:
            VStack(spacing: 0) {
                Text(month)
                    .font(Typeface.paperLabel(24))
                    .foregroundStyle(Ink.text.opacity(0.75))
                Text(day)
                    .font(Typeface.numeral(size: 160))
                    .foregroundStyle(Ink.text.opacity(0.88))
                    .padding(.vertical, -8)
                Text(weekday)
                    .font(Typeface.paperLabel(20))
                    .foregroundStyle(Ink.text.opacity(0.6))
            }

        default:
            VStack(spacing: 0) {
                Text(month)
                    .font(Typeface.paperLabel(14))
                    .foregroundStyle(Ink.text.opacity(0.75))
                Text(day)
                    .font(Typeface.numeral(size: 74))
                    .foregroundStyle(Ink.text.opacity(0.88))
                    .padding(.vertical, -6)
                Text(weekday)
                    .font(Typeface.paperLabel(13))
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
        }
    }
}
