import SwiftUI

struct StickerDrawer: View {
    let isOpen: Bool
    let toggle: () -> Void
    let choose: (StickerAsset) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var hasPeeked = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: typeSize.isAccessibilitySize ? 2 : 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: Space.sm) {
                    Text("stickers")
                        .font(Typeface.heading)
                    Spacer(minLength: Space.xs)
                    peek
                    Image(systemName: "chevron.down")
                        .font(Typeface.iconSmall)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(Ink.muted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.md)
                .frame(minHeight: Size.drawerLip)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(PaperGlassColor.drawer)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sticker-drawer")
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            .zIndex(1)

            if isOpen {
                LazyVGrid(columns: columns, spacing: Space.xs) {
                    ForEach(StickerCatalog.items) { asset in
                        StickerTile(asset: asset) { choose(asset) }
                    }
                }
                .padding(Space.sm)
                .transition(reduceMotion ? .opacity : .offset(y: -Space.xs).combined(with: .opacity))
            }
        }
        .foregroundStyle(Ink.text)
        .background(.white, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Ink.hairline)
                .allowsHitTesting(false)
        }
        .onAppear {
            if reduceMotion {
                hasPeeked = true
            } else {
                withAnimation(.easeOut(duration: 0.32)) { hasPeeked = true }
            }
        }
    }

    private var peek: some View {
        let fanned = hasPeeked && isOpen
        return ZStack {
            ForEach(StickerCatalog.drawerPreview) { asset in
                let leading = asset.id == "frog"
                StickerArt(asset: asset)
                    .padding(leading ? Space.xxs : 0)
                    .frame(width: Size.stickerThumb, height: Size.stickerThumb)
                    .background(asset.tint.fill, in: RoundedRectangle(cornerRadius: Space.xs, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: Space.xs, style: .continuous).strokeBorder(asset.tint.edge) }
                    .rotationEffect(.degrees(fanned ? (leading ? -14 : 12) : (leading ? -7 : 5)))
                    .offset(x: (leading ? -1 : 1) * (fanned ? Space.sm : Space.xs),
                            y: fanned ? (leading ? -Space.sm : -Space.xs) : Space.xxs)
            }
        }
        .frame(width: Size.drawerPreview, height: Size.stickerThumb)
        .accessibilityHidden(true)
    }
}

private struct StickerTile: View {
    let asset: StickerAsset
    let choose: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: choose) {
            VStack(spacing: Space.xxs) {
                StickerArt(asset: asset)
                    .frame(width: Size.drawerArt, height: Size.drawerArt)
                    .rotationEffect(.degrees(asset.tint.tilt))
                    .accessibilityHidden(true)
                Text(asset.name)
                    .font(Typeface.caption)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.xxs)
            .frame(maxWidth: .infinity, minHeight: Size.drawerTile)
            .background(asset.tint.fill, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(asset.tint.edge) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tray-\(asset.id)")
    }
}

struct StickerPlacementPrompt: View {
    let asset: StickerAsset
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Space.sm) {
            StickerArt(asset: asset)
                .frame(width: Size.stickerThumb, height: Size.stickerThumb)
                .accessibilityHidden(true)
            Text("tap the note to place \(asset.name)")
                .font(Typeface.subhead)
                .accessibilityIdentifier("placement-hint")
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark")
                    .font(Typeface.iconSmall)
                    .frame(width: Size.tapTarget, height: Size.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("cancel sticker placement")
            .accessibilityIdentifier("cancel-placement")
        }
        .padding(.leading, Space.sm)
        .padding(.trailing, Space.xxs)
        .foregroundStyle(Ink.text)
        .background(asset.tint.fill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

struct StickerInspector: View {
    let asset: StickerAsset
    @Binding var scale: Double
    @Binding var rotation: Double
    let commit: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                StickerArt(asset: asset)
                    .frame(width: Size.stickerThumb, height: Size.stickerThumb)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(asset.name).font(Typeface.heading)
                    Text("drag to move").font(Typeface.caption).foregroundStyle(Ink.muted)
                }
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                        .font(Typeface.icon)
                        .foregroundStyle(CraftTint.peach.ink)
                        .frame(width: Size.tapTarget, height: Size.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("delete \(asset.name)")
                .accessibilityIdentifier("delete-decoration")
            }
            adjustment("size", value: $scale, range: PlacedSticker.scaleRange,
                       readout: scale.formatted(.percent.precision(.fractionLength(0))))
            adjustment("rotation", value: $rotation, range: PlacedSticker.rotationRange,
                       readout: "\(Int(rotation.rounded()))°")
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .background(.white, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Ink.hairline) }
        .foregroundStyle(Ink.text)
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, readout: String) -> some View {
        HStack(spacing: Space.xs) {
            Text(title)
                .font(Typeface.subhead)
                .frame(minWidth: Size.sliderLabel, alignment: .leading)
                .accessibilityHidden(true)
            Slider(value: value, in: range, onEditingChanged: { editing in
                if !editing { commit() }
            })
            .tint(Ink.text)
            .accessibilityLabel(title)
            .accessibilityValue(readout)
            .accessibilityIdentifier("decoration-\(title)")
            Text(readout)
                .font(Typeface.callout)
                .foregroundStyle(Ink.muted)
                .frame(minWidth: Size.sliderLabel, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Size.tapTarget)
    }
}
