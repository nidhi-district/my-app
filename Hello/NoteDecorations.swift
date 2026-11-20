import SwiftUI

struct StickerAsset: Identifiable {
    let id: String
    let name: String
    let tint: CraftTint
    let image: String
}

enum StickerCatalog {
    static let items: [StickerAsset] = [
        .init(id: "frog", name: "frog", tint: .mint, image: "StickerFrog"),
        .init(id: "cat", name: "sleepy cat", tint: .butter, image: "StickerCat"),
        .init(id: "cherries", name: "cherries", tint: .peach, image: "StickerCherries"),
        .init(id: "mushroom", name: "mushroom", tint: .lavender, image: "StickerMushroom"),
        .init(id: "tea", name: "tea", tint: .peach, image: "StickerTea"),
        .init(id: "moon", name: "moon", tint: .butter, image: "StickerMoon"),
        .init(id: "flowers", name: "flowers", tint: .mint, image: "StickerFlowers"),
        .init(id: "letter", name: "letter", tint: .lavender, image: "StickerLetter"),
    ]

    static let drawerPreview = ["frog", "cherries"].compactMap(asset(id:))

    static func asset(id: String) -> StickerAsset? { items.first { $0.id == id } }
}

struct PlacedSticker: Identifiable, Codable {
    static let scaleRange = 0.4...1.65
    static let rotationRange = -180.0...180.0

    var id = UUID()
    let assetID: String
    var x: Double
    var y: Double
    var rotation: Double = 0
    // Optional for notes saved before the editor supported resizing.
    var scale: Double?

    var displayScale: Double {
        get { scale ?? 1 }
        set { scale = newValue }
    }
    var asset: StickerAsset? { StickerCatalog.asset(id: assetID) }

    func center(in size: CGSize) -> CGPoint {
        CGPoint(x: x * size.width, y: y * size.height)
    }

    func contains(_ point: CGPoint, on note: CGFloat) -> Bool {
        guard asset != nil else { return false }
        let dx = point.x - x * note
        let dy = point.y - y * note
        let angle = rotation * .pi / 180
        let localX = dx * cos(angle) + dy * sin(angle)
        let localY = -dx * sin(angle) + dy * cos(angle)
        let half = max(Size.tapTarget, Size.placedSticker * displayScale) / 2
        return abs(localX) <= half && abs(localY) <= half
    }

    mutating func move(to point: CGPoint, on note: CGFloat) {
        guard note > 0 else { return }
        let angle = rotation * .pi / 180
        let side = Size.placedSticker * displayScale
        let rotatedHalf = side * (abs(cos(angle)) + abs(sin(angle))) / 2
        let inset = min(0.5, (rotatedHalf + Space.xs) / note)
        x = min(max(point.x / note, inset), 1 - inset)
        y = min(max(point.y / note, inset), 1 - inset)
    }
}

enum StickerStorage {
    static let widgetKind = "NotePad"
    private static let group = "group.com.nidhisingh.hello"
    private static var testSuffix: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sticker-test") { return ".uitest" }
        #endif
        return ""
    }
    private static var storageKey: String { "stillday.placed-stickers.v1\(testSuffix)" }
    private static var sharedFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("note-decorations\(testSuffix).json")
    }

    static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func load(forWidget: Bool = false) -> [String: [PlacedSticker]] {
        let data = forWidget
            ? sharedFile.flatMap { try? Data(contentsOf: $0) }
            : UserDefaults.standard.data(forKey: storageKey)
        guard let data, let pages = try? JSONDecoder().decode([String: [PlacedSticker]].self, from: data) else { return [:] }
        return pages
    }

    /// Copy existing app-local notes into the shared store on the first launch after upgrading.
    @discardableResult
    static func migrate() -> Bool {
        guard let sharedFile, !FileManager.default.fileExists(atPath: sharedFile.path),
              UserDefaults.standard.data(forKey: storageKey) != nil else { return false }
        return save(load())
    }

    /// Returns true once the widget can read the new state. Local storage also supports unsigned builds.
    @discardableResult
    static func save(_ pages: [String: [PlacedSticker]]) -> Bool {
        guard let data = try? JSONEncoder().encode(pages) else { return false }
        UserDefaults.standard.set(data, forKey: storageKey)
        guard let sharedFile else { return false }
        do {
            try data.write(to: sharedFile, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}

struct StickerArt: View {
    let asset: StickerAsset

    var body: some View {
        Image(asset.image).resizable().scaledToFit()
    }
}

struct PlacedStickerLayer: View {
    let stickers: [PlacedSticker]
    var selected: UUID?
    var landing: UUID?
    var onSelect: ((UUID) -> Void)?
    var scalesToCanvas = false

    var body: some View {
        GeometryReader { geometry in
            let factor = scalesToCanvas ? min(geometry.size.width, geometry.size.height) / Size.noteMax : 1
            ForEach(stickers) { sticker in
                if let asset = sticker.asset {
                    let side = Size.placedSticker * sticker.displayScale * factor
                    Group {
                        if landing == sticker.id {
                            LandingSticker(asset: asset, isSelected: selected == sticker.id)
                        } else {
                            StickerPressArtwork(asset: asset, isSelected: selected == sticker.id, progress: 1)
                        }
                    }
                        .frame(width: side, height: side)
                        .transition(.opacity)
                        .rotationEffect(.degrees(sticker.rotation))
                        .position(sticker.center(in: geometry.size))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(asset.name)
                        .accessibilityIdentifier("placed-\(asset.id)")
                        .accessibilityHidden(onSelect == nil)
                        .accessibilityAddTraits(selected == sticker.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { onSelect?(sticker.id) }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LandingSticker: View {
    let asset: StickerAsset
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        StickerPressArtwork(asset: asset, isSelected: isSelected, progress: reduceMotion ? 1 : progress)
            .task {
                if !reduceMotion {
                    withAnimation(.easeIn(duration: 0.10)) { progress = StickerPressArtwork.contactMoment }
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.timingCurve(0.32, 0, 0.35, 1, duration: 0.36)) { progress = 1 }
            }
    }
}

/// A strip of flexible paper bends above the moving contact line. The part below
/// the line stays stationary as pressure rolls the lifted section onto the page.
private struct StickerPressArtwork: View, Animatable {
    static let contactMoment: CGFloat = 0.22
    let asset: StickerAsset
    let isSelected: Bool
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        if progress >= 1 {
            StickerArt(asset: asset)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(Ink.muted, style: StrokeStyle(lineWidth: 1, dash: [Space.xxs]))
                            .padding(-Space.xxs)
                    }
                }
        } else {
            Canvas { context, available in
                let image = context.resolve(Image(asset.image))
                guard image.size.width > 0, image.size.height > 0 else { return }
                let fit = min(available.width / image.size.width, available.height / image.size.height)
                let width = image.size.width * fit
                let height = image.size.height * fit
                let x = (available.width - width) / 2
                let bottom = (available.height + height) / 2
                let approach = min(1, progress / Self.contactMoment)
                let press = max(0, (progress - Self.contactMoment) / (1 - Self.contactMoment))
                let free = height * (1 - press)
                let contactY = bottom - height * press
                let angle: CGFloat = 1.12
                let radius = free / angle

                // Draw the raised area as adjacent bands along a cylindrical curl.
                // sin projects arc length onto the page, with unit slope at the contact line.
                func paintCurl(_ graphics: GraphicsContext, lift: CGFloat) {
                    guard free > 0 else { return }
                    let bands = 18
                    for index in 0..<bands {
                        let a = CGFloat(index) / CGFloat(bands)
                        let b = CGFloat(index + 1) / CGFloat(bands)
                        let near = contactY - lift - radius * sin(angle * a)
                        let far = contactY - lift - radius * sin(angle * b)
                        let sourceBand = free * (b - a)
                        let scale = (near - far) / sourceBand
                        let sourceY = free * (1 - b)
                        var band = graphics
                        band.clip(to: Path(CGRect(x: x, y: far, width: width, height: near - far)),
                                  style: FillStyle(antialiased: false))
                        band.draw(image, in: CGRect(x: x, y: far - sourceY * scale,
                                                    width: width, height: height * scale))
                    }
                }

                let lift = Space.sm * (1 - approach)
                let depth = radius * (1 - cos(angle))
                var shadow = context
                shadow.addFilter(.shadow(color: Ink.text.opacity(0.23 * (1 - press)),
                                         radius: Space.xxs + depth * 0.16,
                                         y: Space.xxs + (lift + depth) * 0.20,
                                         options: .shadowOnly))
                shadow.drawLayer { paintCurl($0, lift: 0) }

                var attached = context
                attached.clip(to: Path(CGRect(x: x, y: contactY, width: width, height: height * press)),
                              style: FillStyle(antialiased: false))
                attached.draw(image, in: CGRect(x: x, y: bottom - height, width: width, height: height))
                paintCurl(context, lift: lift)
            }
        }
    }
}
