import SwiftUI
import WidgetKit

@main
struct HelloApp: App {
    init() {
        Typeface.registerBundledFonts()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-stickers") {
            StickerStorage.save([:])
            WidgetCenter.shared.reloadTimelines(ofKind: StickerStorage.widgetKind)
            return
        }
        #endif
        if StickerStorage.migrate() {
            WidgetCenter.shared.reloadTimelines(ofKind: StickerStorage.widgetKind)
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-widgets") { WidgetGallery().textCase(.lowercase) } else { TodayScreen().textCase(.lowercase) }
            #else
            TodayScreen().textCase(.lowercase)   // house rule: all text is lowercase (README §1)
            #endif
        }
    }
}

// MARK: - Screen

struct TodayScreen: View {
    @State private var date = Date()
    @State private var tab = CalendarTab.day
    @State private var overviewDate = Date()
    @State private var calendarScrollActivity = CalendarScrollActivity.idle
    @State private var isTabBarCompact = false
    @State private var isEditingNote = false
    @State private var isTurningPage = false
    @State private var selectedID: UUID?
    @State private var landingID: UUID?
    @State private var pendingAsset: StickerAsset?
    @State private var isDrawerOpen = false
    @State private var dragOrigin: PlacedSticker?
    @State private var stickerPages = StickerStorage.load()
    @State private var needsSave = false
    @ScaledMetric(relativeTo: .caption) private var tabHeight = Size.tabHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            tabScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(tab)
                .transition(tabTransition)
        }
        .clipped()
        .font(Typeface.body)
        // Leave enough room to scroll the last row above the bar while drawing content behind it.
        .contentMargins(.bottom, tabHeight + Space.xs * 2 + Space.xxs, for: .scrollContent)
        .usesCalendarBottomFade()
        .overlay(alignment: .bottom) {
            CalendarTabBar(selection: tab, isCompact: isTabBarCompact, tabHeight: tabHeight, select: selectTab)
                .disabled(isTurningPage)
        }
        .background(Ink.canvas.ignoresSafeArea())
        .task(id: calendarScrollActivity) { await restoreTabBarAfterScroll() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveChanges() }
        }
    }

    @ViewBuilder private var tabScreen: some View {
        switch tab {
        case .day: dayScreen
        case .week:
            WeekOverview(date: date, period: $overviewDate, stickersForDate: stickers(for:), openDay: openDay) {
                calendarScrollChanged($0, in: .week)
            }
        case .year:
            YearOverview(date: date, period: $overviewDate, stickersForDate: stickers(for:), openDay: openDay) {
                calendarScrollChanged($0, in: .year)
            }
        }
    }

    private var tabTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .offset(y: Space.sm).combined(with: .opacity),
                           removal: .opacity)
    }

    private var dayScreen: some View {
        GeometryReader { proxy in
            let noteSize = min(Size.noteMax, proxy.size.width - Space.margin * 2)
            let travel = max(proxy.size.width, proxy.size.height) + noteSize
            VStack(spacing: Space.sm) {
                Header(date: date, isEditingNote: isEditingNote, isTurningPage: isTurningPage, edit: toggleEditing)
                    .padding(.horizontal, Space.margin)
                    .zIndex(1)
                ScrollViewReader { scroll in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: Space.md) {
                            StickyNoteStack(date: $date,
                                            size: noteSize,
                                            viewportTravel: travel,
                                            isEditing: isEditingNote,
                                            stickersForDate: stickers(for:),
                                            selectedSticker: selectedID,
                                            landingSticker: landingID,
                                            placementHint: placementHint,
                                            onEditTap: { tapNote(at: $0, size: noteSize) },
                                            onSelectSticker: selectSticker,
                                            onEditDrag: { dragNote(from: $0, by: $1, size: noteSize) },
                                            onEditDragEnd: endDrag,
                                            onPeelStateChanged: { isTurningPage = $0 })
                                .id("day-page")

                            if isEditingNote {
                                editorControls(noteSize: noteSize)
                                    .frame(width: noteSize)
                            }
                        }
                        .padding(.top, Space.xs)
                        .padding(.horizontal, Space.margin)
                        .padding(.bottom, Space.xl)
                    }
                    .onCalendarScrollActivity { calendarScrollChanged($0, in: .day) }
                    .onChange(of: isEditingNote) { _, editing in
                        if editing { scroll.scrollTo("day-page", anchor: .top) }
                    }
                }
            }
        }
    }

    private func selectTab(_ newTab: CalendarTab) {
        guard tab != newTab, !isTurningPage else { return }
        if tab == .day {
            overviewDate = date
            if isEditingNote { endEditing() }
        }
        let animation: Animation = reduceMotion ? .easeOut(duration: 0.16) : .easeInOut(duration: 0.28)
        withAnimation(animation) {
            tab = newTab
            calendarScrollActivity = .idle
            isTabBarCompact = false
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func calendarScrollChanged(_ activity: CalendarScrollActivity, in source: CalendarTab) {
        guard source == tab else { return }
        calendarScrollActivity = activity
        switch activity {
        case .fingerUp: setTabBarCompact(false)
        case .fingerDown: setTabBarCompact(true)
        case .idle, .tracking: break
        }
    }

    private func restoreTabBarAfterScroll() async {
        guard calendarScrollActivity == .idle, isTabBarCompact else { return }
        do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
        guard !Task.isCancelled, calendarScrollActivity == .idle else { return }
        setTabBarCompact(false)
    }

    private func setTabBarCompact(_ compact: Bool) {
        guard compact != isTabBarCompact else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: compact ? 0.38 : 0.30)) {
            isTabBarCompact = compact
        }
    }

    private func openDay(_ selected: Date) {
        date = selected
        selectTab(.day)
    }

    private var placementHint: String? {
        pendingAsset.map { "tap the note to place \($0.name)" }
    }

    private var currentPieces: [PlacedSticker] { stickers(for: date) }

    private var drawerAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.24)
    }

    private func editorControls(noteSize: CGFloat) -> some View {
        VStack(spacing: Space.xs) {
            if let pendingAsset {
                StickerPlacementPrompt(asset: pendingAsset, cancel: toggleDrawer)
            } else if let piece = currentPieces.first(where: { $0.id == selectedID }), let asset = piece.asset {
                StickerInspector(asset: asset,
                                 scale: adjustment(for: piece.id, \.displayScale, fallback: 1, size: noteSize),
                                 rotation: adjustment(for: piece.id, \.rotation, fallback: 0, size: noteSize),
                                 commit: saveChanges,
                                 delete: { delete(piece.id) })
            }
            StickerDrawer(isOpen: isDrawerOpen, toggle: toggleDrawer, choose: choose)
        }
    }

    private func toggleEditing() {
        if isEditingNote {
            endEditing()
        } else {
            isDrawerOpen = true
            isEditingNote = true
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func endEditing() {
        saveChanges()
        selectedID = nil
        landingID = nil
        pendingAsset = nil
        dragOrigin = nil
        isDrawerOpen = false
        isEditingNote = false
    }

    private func toggleDrawer() {
        saveChanges()
        withAnimation(drawerAnimation) {
            isDrawerOpen.toggle()
            if isDrawerOpen {
                pendingAsset = nil
                selectedID = nil
            }
        }
    }

    private func choose(_ asset: StickerAsset) {
        withAnimation(drawerAnimation) {
            selectedID = nil
            pendingAsset = asset
            isDrawerOpen = false
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func selectSticker(_ id: UUID) {
        if isDrawerOpen {
            withAnimation(drawerAnimation) { isDrawerOpen = false }
        }
        selectedID = id
        pendingAsset = nil
    }

    private func stickers(for date: Date) -> [PlacedSticker] {
        stickerPages[StickerStorage.dayKey(for: date)] ?? []
    }

    private func tapNote(at point: CGPoint, size: CGFloat) {
        if let asset = pendingAsset {
            var piece = PlacedSticker(assetID: asset.id, x: 0.5, y: 0.5, rotation: asset.tint.tilt)
            piece.move(to: point, on: size)
            pendingAsset = nil
            selectedID = piece.id
            landingID = piece.id
            setPieces(currentPieces + [piece])
            saveChanges()
        } else {
            if let piece = piece(at: point, size: size) {
                selectSticker(piece.id)
            } else {
                selectedID = nil
            }
        }
    }

    private func piece(at point: CGPoint, size: CGFloat) -> PlacedSticker? {
        currentPieces.reversed().first { $0.contains(point, on: size) }
    }

    private func dragNote(from start: CGPoint, by translation: CGSize, size: CGFloat) {
        guard pendingAsset == nil else { return }
        if dragOrigin == nil, let piece = piece(at: start, size: size) {
            dragOrigin = piece
            selectSticker(piece.id)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        guard var piece = dragOrigin else { return }
        piece.move(to: CGPoint(x: piece.x * size + translation.width, y: piece.y * size + translation.height),
                   on: size)
        replace(piece)
    }

    private func endDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        saveChanges()
    }

    private func adjustment(for id: UUID, _ keyPath: WritableKeyPath<PlacedSticker, Double>,
                            fallback: Double, size: CGFloat) -> Binding<Double> {
        Binding {
            currentPieces.first { $0.id == id }?[keyPath: keyPath] ?? fallback
        } set: { value in
            guard var piece = currentPieces.first(where: { $0.id == id }) else { return }
            piece[keyPath: keyPath] = value
            piece.move(to: piece.center(in: CGSize(width: size, height: size)), on: size)
            replace(piece)
        }
    }

    private func replace(_ piece: PlacedSticker) {
        var pieces = currentPieces
        guard let index = pieces.firstIndex(where: { $0.id == piece.id }) else { return }
        pieces[index] = piece
        setPieces(pieces)
    }

    private func delete(_ id: UUID) {
        selectedID = nil
        withAnimation(.easeOut(duration: 0.15)) {
            setPieces(currentPieces.filter { $0.id != id })
        }
        saveChanges()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func setPieces(_ pieces: [PlacedSticker]) {
        let key = StickerStorage.dayKey(for: date)
        stickerPages[key] = pieces.isEmpty ? nil : pieces
        needsSave = true
    }

    private func saveChanges() {
        guard needsSave else { return }
        if StickerStorage.save(stickerPages) {
            WidgetCenter.shared.reloadTimelines(ofKind: StickerStorage.widgetKind)
        }
        needsSave = false
    }
}

private struct Header: View {
    let date: Date
    let isEditingNote: Bool
    let isTurningPage: Bool
    let edit: () -> Void

    var body: some View {
        HStack {
            GlassIcon(symbol: "line.3.horizontal", label: "menu") {}
            Spacer()
            Text(date.formatted(.dateTime.day().month(.wide)))
                .font(Typeface.dateHeading)
                .foregroundStyle(Ink.text)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.35), value: date)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("active-date")
            Spacer()
            GlassIcon(symbol: isEditingNote ? "checkmark" : "pencil",
                      label: isEditingNote ? "finish editing note" : "edit note",
                      identifier: "edit-note",
                      action: edit)
                .disabled(isTurningPage)
        }
        .padding(.top, Space.xs)
    }
}

struct GlassIcon: View {
    var symbol: String
    var label: String
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Typeface.icon)
                .foregroundStyle(Ink.text)
                .frame(width: Size.tapTarget, height: Size.tapTarget)
                .glass(Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? label)
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View { TodayScreen() }
}

#if DEBUG
/// Debug-only: the home-screen widget in all three sizes, at iPhone widget dimensions.
private struct WidgetGallery: View {
    var body: some View {
        VStack(spacing: Space.lg) {
            HStack(spacing: Space.lg) {
                tile(.systemSmall, CGSize(width: 158, height: 158))
                tile(.systemSmall, CGSize(width: 158, height: 158))
            }
            tile(.systemMedium, CGSize(width: 338, height: 158))
            tile(.systemLarge, CGSize(width: 338, height: 354))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.55, green: 0.62, blue: 0.72), Color(red: 0.78, green: 0.70, blue: 0.66)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func tile(_ family: WidgetFamily, _ size: CGSize) -> some View {
        let date = Date.now
        let pieces = StickerStorage.load(forWidget: true)[StickerStorage.dayKey(for: date)] ?? []
        return WidgetPad(date: date, family: family, bounds: size, stickers: pieces)
            .frame(width: size.width, height: size.height)
            .background(Ink.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
