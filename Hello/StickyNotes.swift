import SwiftUI
import AVFoundation

// MARK: - Stack with peel-to-change-day

/// Lock the dominant axis of a swipe once the paper is gripped.
private enum PageSwipe {
    case up, down, left, right

    init(_ translation: CGSize) {
        if abs(translation.width) > abs(translation.height) {
            self = translation.width < 0 ? .left : .right
        } else {
            self = translation.height < 0 ? .up : .down
        }
    }

    var offset: Int { self == .up || self == .left ? 1 : -1 }

    var vector: CGVector {
        switch self {
        case .up: CGVector(dx: 0, dy: -1)
        case .down: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
    }
}

/// A pad of sticky notes that turns one day per swipe.
struct StickyNoteStack: View {
    @Binding var date: Date
    var size: CGFloat = Size.noteMax
    var viewportTravel: CGFloat = 1120
    var isEditing = false
    var stickersForDate: (Date) -> [PlacedSticker] = { _ in [] }
    var selectedSticker: UUID?
    var landingSticker: UUID?
    var placementHint: String?
    var onEditTap: (CGPoint) -> Void = { _ in }
    var onSelectSticker: (UUID) -> Void = { _ in }
    var onEditDrag: (CGPoint, CGSize) -> Void = { _, _ in }
    var onEditDragEnd: () -> Void = {}
    var onPeelStateChanged: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Peel state, in the top note's own coordinates.
    @State private var grab: CGPoint = .zero
    @State private var finger: CGPoint = .zero
    @State private var swipe = PageSwipe.up
    // Throw state. Horizontal travel, vertical travel and gravity are separate so each gets its own curve,
    // which gives the sheet a real arc instead of a straight slide.
    @State private var flyX: CGFloat = 0
    @State private var flyY: CGFloat = 0
    @State private var flyDrop: CGFloat = 0
    @State private var flySpin: Double = 0
    @State private var flyTilt: Double = 0
    @State private var flyAxis = CGVector(dx: 0, dy: 1)
    @State private var flyLift: CGFloat = 1
    @State private var busy = false
    @State private var peeling = false
    /// Once a swipe has picked which edge it holds, it keeps holding that edge.
    @State private var gripLocked = false
    /// Pulled past the tear point (letting go now tears it off).
    @State private var armed = false
    /// Previous drag sample, for measuring how fast the paper is moving.
    @State private var lastDrag: (t: CGSize, time: Date) = (.zero, .distantPast)

    private var targetDate: Date { Calendar.current.date(byAdding: .day, value: swipe.offset, to: date) ?? date }

    var body: some View {
        ZStack {
            // The pad's body: a block of sheets whose edges show along the bottom, on a backing board.
            PadBlock(size: size)
                .allowsHitTesting(false)

            // The note that will be revealed.
            NoteFace(date: targetDate, stickers: stickersForDate(targetDate))
                .frame(width: size, height: size)
                .paperShadow()
                .allowsHitTesting(false)

            // The top note, which folds as it is peeled.
            FoldingNote(grab: grab, finger: finger, size: size,
                        front: NoteFace(date: date, stickers: stickersForDate(date),
                                        selectedSticker: selectedSticker,
                                        landingSticker: landingSticker,
                                        onSelectSticker: isEditing ? onSelectSticker : nil),
                        back: NoteBack(date: date))
                .frame(width: size, height: size)
                .scaleEffect(flyLift)
                .rotation3DEffect(.degrees(flyTilt), axis: (x: flyAxis.dx, y: flyAxis.dy, z: 0), perspective: 0.45)
                .rotationEffect(.degrees(flySpin))
                .offset(x: flyX, y: flyY + flyDrop)
                .allowsHitTesting(false)

            // Touch surface for the note. UIKit, so the page's scroll view waits for it instead of stealing
            // the swipe partway through (a SwiftUI drag inside a ScrollView gets cancelled after one move).
            // It also carries the note's accessibility, since its frame is exactly the note's.
            PeelTouchSurface(onTap: { point in
                if isEditing { onEditTap(point) }
            }, onDrag: { start, translation in
                if isEditing { onEditDrag(start, translation) } else { dragChanged(translation) }
            }, onEnd: { velocity in
                if isEditing { onEditDragEnd() } else { release(velocity: velocity) }
            })
                .frame(width: size, height: size)
                .accessibilityElement()
                .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .accessibilityValue(stickerAccessibilityValue)
                .accessibilityHint(isEditing ? placementHint ?? "select a sticker to adjust it" : "")
                .accessibilityIdentifier("note")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    if isEditing, placementHint != nil {
                        onEditTap(CGPoint(x: size * 0.75, y: size * 0.75))
                    }
                }
                .accessibilityActions {
                    if !isEditing {
                        Button("next day") { turnPage(.up) }
                        Button("previous day") { turnPage(.down) }
                    }
                }

            // Metal rings through the binding holes. They belong to the pad, so they stay when a sheet goes.
            RingBinding(size: size)
                .frame(width: size, height: size)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: size + Space.xl)
        .zIndex(1)   // the thrown sheet flies over whatever is below the pad
        .onAppear(perform: debugPeelIfRequested)
        .onChange(of: busy || peeling) { _, turning in onPeelStateChanged(turning) }
    }

    private var stickerAccessibilityValue: String {
        let count = stickersForDate(date).filter { $0.asset != nil }.count
        return count == 1 ? "1 sticker placed" : "\(count) stickers placed"
    }

    // MARK: Gesture

    /// Finger moved on the note. `t` is the translation since touch-down, in the note's coordinates.
    private func dragChanged(_ t: CGSize) {
        guard !busy else { return }
        let len = hypot(t.width, t.height)
        guard len > 1 else { return }
        let now = Date()
        if !peeling {
            peeling = true
            gripLocked = false
            armed = false
            lastDrag = (t, now)
            UISelectionFeedbackGenerator().selectionChanged()
            PaperSound.shared.beginRustle()
        }
        if !gripLocked {
            swipe = PageSwipe(t)
            grab = edgePoint(opposite: swipe.vector)
            if len > 14 { gripLocked = true }
        }
        let axis = swipe.vector
        let along = max(0, (t.width * axis.dx + t.height * axis.dy) * 0.92)
        let cross = (t.height * axis.dx - t.width * axis.dy) * 0.50
        let sway = min(along * 0.35, max(-along * 0.35, cross))
        if reduceMotion {
            finger = grab
        } else {
            finger = CGPoint(x: grab.x + axis.dx * along - axis.dy * sway,
                             y: grab.y + axis.dy * along + axis.dx * sway)
        }

        // Paper rustles with movement: louder the faster it moves, silent when held still.
        let dt = max(now.timeIntervalSince(lastDrag.time), 1.0 / 240)
        let moved = hypot(t.width - lastDrag.t.width, t.height - lastDrag.t.height)
        PaperSound.shared.rustle(speed: moved / dt)
        lastDrag = (t, now)

        // A small tick when it has been pulled far enough that letting go will tear it.
        let tears = along > tearDistance
        if tears != armed {
            armed = tears
            UIImpactFeedbackGenerator(style: tears ? .light : .soft).impactOccurred(intensity: 0.6)
        }
    }

    /// How far the sheet must be peeled for letting go to tear it off.
    private var tearDistance: CGFloat { size * 0.32 }

    /// Turn once on a long drag or a short flick in the locked direction.
    private func release(velocity: CGVector?) {
        guard !busy, peeling else { return }
        peeling = false
        PaperSound.shared.endRustle()
        let axis = swipe.vector
        let pulled = (lastDrag.t.width * axis.dx + lastDrag.t.height * axis.dy) * 0.92
        guard let velocity,
              armed || ((velocity.dx * axis.dx + velocity.dy * axis.dy) > 650 && pulled > 12) else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.66)) { finger = grab }
            return
        }
        busy = true
        PaperSound.shared.playPeel()
        guard !reduceMotion else {
            completeTurn()
            return
        }
        let peel = max(pulled, size * 0.52)
        withAnimation(.easeOut(duration: 0.10)) {
            finger = CGPoint(x: grab.x + axis.dx * peel, y: grab.y + axis.dy * peel)
        } completion: {
            detach()
        }
    }

    private func turnPage(_ direction: PageSwipe) {
        guard !busy, !peeling, !isEditing else { return }
        busy = true
        swipe = direction
        PaperSound.shared.playPeel()
        guard !reduceMotion else {
            completeTurn()
            return
        }
        let axis = direction.vector
        grab = edgePoint(opposite: axis)
        finger = grab
        withAnimation(.easeIn(duration: 0.18)) {
            finger = grab + axis * (size * 0.52)
        } completion: {
            detach()
        }
    }

    /// Fly off along the swipe axis and keep the revealed date fixed underneath.
    private func detach() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        PaperSound.shared.playWhoosh()
        let axis = swipe.vector
        let duration = 0.52

        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { flyAxis = CGVector(dx: -axis.dy, dy: axis.dx) }

        withAnimation(.easeOut(duration: 0.24)) {
            finger = grab + axis * (size * 0.90)
            flyLift = 1.08
            flyTilt = 36
        }
        withAnimation(.easeIn(duration: duration)) {
            flySpin = axis.dx * 22
            flyDrop = abs(axis.dx) * size * 0.18
        }
        withAnimation(.timingCurve(0.42, 0, 0.72, 0.90, duration: duration)) {
            flyX = axis.dx * viewportTravel
            flyY = axis.dy * viewportTravel
        } completion: {
            completeTurn()
        }
    }

    private func completeTurn() {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            date = targetDate
            grab = .zero; finger = .zero
            flyX = 0; flyY = 0; flyDrop = 0; flySpin = 0; flyTilt = 0; flyLift = 1
            busy = false
        }
    }

    // MARK: Geometry helpers

    /// Point on the note's edge (a corner for diagonal pulls) furthest against direction `w`.
    private func edgePoint(opposite w: CGVector) -> CGPoint {
        let half = size / 2
        let scale = half / max(abs(w.dx), abs(w.dy), 0.001)
        return CGPoint(x: half - w.dx * scale, y: half - w.dy * scale)
    }

    /// Debug: `-peel 0.4` freezes the note mid-peel for screenshots.
    private func debugPeelIfRequested() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-peel"), i + 1 < args.count, let p = Double(args[i + 1]) {
            grab = CGPoint(x: size, y: size)
            finger = CGPoint(x: size - size * p * 1.1, y: size - size * p * 1.3)
        }
        // `-fold gx gy fx fy` freezes a fold from grab to finger (fractions of the note) for screenshots.
        if let i = args.firstIndex(of: "-fold"), i + 4 < args.count {
            let v = (1...4).compactMap { Double(args[i + $0]) }.map { CGFloat($0) * size }
            if v.count == 4 { grab = CGPoint(x: v[0], y: v[1]); finger = CGPoint(x: v[2], y: v[3]) }
        }
        if args.contains("-autopeel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { turnPage(.up) }
        }
        #endif
    }
}

// MARK: - Touch

/// Tap and pan recognisers for the note, in UIKit.
///
/// Why not a SwiftUI `DragGesture`: inside a `ScrollView`, the scroll view's own pan recogniser takes over a
/// swipe after its first movement and the SwiftUI drag is cancelled, so the sheet just falls back. Here the
/// enclosing scroll view is told to wait for our pan to fail, which it only does for touches outside the note.
struct PeelTouchSurface: UIViewRepresentable {
    var onTap: (CGPoint) -> Void
    /// Start and translation since touch-down, in this view's coordinates.
    var onDrag: (CGPoint, CGSize) -> Void
    /// Velocity in points per second when the finger lifts; `nil` if the touch was cancelled.
    var onEnd: (CGVector?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        view.pan = pan
        context.coordinator.parent = self
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject {
        var parent: PeelTouchSurface?

        @objc func tap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            parent?.onTap(g.location(in: v))
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let v = g.view else { return }
            switch g.state {
            case .began, .changed:
                let t = g.translation(in: v)
                let point = g.location(in: v)
                parent?.onDrag(CGPoint(x: point.x - t.x, y: point.y - t.y), CGSize(width: t.x, height: t.y))
            case .ended:
                let vel = g.velocity(in: v)
                parent?.onEnd(CGVector(dx: vel.x, dy: vel.y))
            case .cancelled, .failed:
                parent?.onEnd(nil)
            default:
                break
            }
        }
    }

    final class TouchView: UIView {
        weak var pan: UIPanGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let pan else { return }
            // Every scroll view above us waits for our pan before scrolling a touch that starts on the note.
            var ancestor = superview
            while let a = ancestor {
                if let scroll = a as? UIScrollView { scroll.panGestureRecognizer.require(toFail: pan) }
                ancestor = a.superview
            }
        }
    }
}

// MARK: - Sound

/// Paper sounds, synthesised so there are no audio files to ship:
/// a crackly "glue letting go" peel, and a soft air whoosh as the sheet is thrown.
/// Uses the ambient session, so it mixes with music and stays quiet when the ringer is silenced.
final class PaperSound {
    static let shared = PaperSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var peels: [AVAudioPCMBuffer] = []
    private var whoosh: AVAudioPCMBuffer?
    private var ready = false

    private init() {
        // A few peel variants so repeated tears don't sound identical.
        peels = (0..<4).compactMap { _ in makePeel() }
        whoosh = makeWhoosh()
        rustleLoop = makeRustle()
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            engine.attach(rustlePlayer)
            engine.connect(rustlePlayer, to: engine.mainMixerNode, format: format)
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }

    func playPeel() { if let b = peels.randomElement() { play(b) } }
    func playWhoosh() { if let b = whoosh { play(b) } }

    // MARK: Rustle — continuous paper sound while the sheet is handled

    private let rustlePlayer = AVAudioPlayerNode()
    private var rustleLoop: AVAudioPCMBuffer?
    private var rustleLevel: Float = 0     // current loudness, eased toward `rustleTarget`
    private var rustleTarget: Float = 0
    private var rustleTimer: Timer?
    private var handling = false

    /// Finger down on the paper: start the (silent) rustle loop so movement can bring it in instantly.
    func beginRustle() {
        guard ready, let loop = rustleLoop else { return }
        if !engine.isRunning { try? engine.start() }
        handling = true
        if !rustlePlayer.isPlaying {
            rustlePlayer.volume = 0
            rustleLevel = 0
            rustlePlayer.scheduleBuffer(loop, at: nil, options: [.loops])
            rustlePlayer.play()
        }
        if rustleTimer == nil {
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            rustleTimer = t
        }
    }

    /// The paper moved at `speed` points per second.
    func rustle(speed: CGFloat) {
        // Perceptual curve: gentle movements are audible, fast ones saturate rather than blare.
        let x = Float(min(speed / 1400, 1))
        rustleTarget = max(rustleTarget, sqrt(x) * 0.9)
    }

    /// Finger lifted: let the rustle fade out.
    func endRustle() { handling = false; rustleTarget = 0 }

    private func tick() {
        // Quick to react, slower to fade, like paper settling.
        let rate: Float = rustleTarget > rustleLevel ? 0.45 : 0.12
        rustleLevel += (rustleTarget - rustleLevel) * rate
        rustlePlayer.volume = rustleLevel
        // The target decays every frame; only continued movement keeps it up. Holding still goes quiet.
        rustleTarget *= 0.80
        if !handling && rustleLevel < 0.005 {
            rustlePlayer.stop()
            rustleTimer?.invalidate()
            rustleTimer = nil
        }
    }

    /// A seamless loop of paper being handled: soft papery hiss, slow crinkle swells and sparse fibre ticks.
    private func makeRustle() -> AVAudioPCMBuffer? {
        buffer(seconds: 2.4) { n, sr, out in
            var hpPrev: Float = 0, hp: Float = 0, lp: Float = 0
            var tick: Float = 0, swell: Float = 0.5, swellTarget: Float = 0.5
            for i in 0..<n {
                let white = Float.random(in: -1...1)
                hp = 0.95 * (hp + white - hpPrev); hpPrev = white
                lp += 0.35 * (hp - lp)
                // Slowly wandering loudness, so it sounds like hands moving rather than static noise.
                if i % (sr / 20) == 0 { swellTarget = Float.random(in: 0.25...1) }
                swell += (swellTarget - swell) * 0.0008
                if Float.random(in: 0...1) < 0.0025 * swell { tick += Float.random(in: 0.2...0.7) * (Bool.random() ? 1 : -1) }
                tick *= 0.8
                out[i] = (lp * 0.35 * swell + tick * 0.35)
            }
            // Crossfade the ends so the loop has no click.
            let fade = sr / 20
            for i in 0..<fade {
                let a = Float(i) / Float(fade)
                out[i] = out[i] * a + out[n - fade + i] * (1 - a)
            }
            for i in (n - fade)..<n { out[i] = out[i - (n - fade)] }
        }
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard ready else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: [])
        if !player.isPlaying { player.play() }
    }

    private func buffer(seconds: Double, _ fill: (Int, Int, UnsafeMutablePointer<Float>) -> Void) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = b.floatChannelData?[0] else { return nil }
        b.frameLength = frames
        fill(Int(frames), Int(format.sampleRate), data)
        return b
    }

    /// Adhesive peel: a dense run of tiny clicks over a papery hiss, densest in the middle.
    private func makePeel() -> AVAudioPCMBuffer? {
        buffer(seconds: 0.42) { n, sr, out in
            var lp: Float = 0, hpPrev: Float = 0, hpOut: Float = 0
            var crackle: Float = 0
            for i in 0..<n {
                let t = Float(i) / Float(n)
                let white = Float.random(in: -1...1)
                // Papery hiss: band-limited around a few kHz.
                hpOut = 0.92 * (hpOut + white - hpPrev); hpPrev = white
                lp += 0.45 * (hpOut - lp)
                // Clicks of glue fibres letting go; density swells then tails off.
                let density = 0.004 + 0.03 * sin(.pi * min(t * 1.3, 1))
                if Float.random(in: 0...1) < density { crackle += Float.random(in: 0.35...1) * (Bool.random() ? 1 : -1) }
                crackle *= 0.82
                let attack = min(Float(i) / (0.012 * Float(sr)), 1)
                let release = min((1 - t) / 0.3, 1)
                let env = attack * release * release
                out[i] = (lp * 0.22 + crackle * 0.5) * env * 0.6
            }
        }
    }

    /// Air rushing past the sheet as it's thrown: low-passed noise that swells and fades.
    private func makeWhoosh() -> AVAudioPCMBuffer? {
        buffer(seconds: 0.55) { n, _, out in
            var a: Float = 0, b: Float = 0
            for i in 0..<n {
                let t = Float(i) / Float(n)
                let white = Float.random(in: -1...1)
                // Cutoff rises then falls with the swell, like something passing by.
                let k: Float = 0.04 + 0.12 * sin(.pi * t)
                a += k * (white - a)
                b += k * (a - b)
                let env = pow(sin(.pi * pow(t, 0.7)), 2)
                out[i] = b * env * 1.1
            }
        }
    }
}

// MARK: - The fold

/// Folds the note along the perpendicular bisector of `grab` → `finger`.
/// The part past the fold line is mirrored across it and shows the back of the paper.
struct FoldingNote<Front: View, Back: View>: View, Animatable {
    var grab: CGPoint
    var finger: CGPoint
    var size: CGFloat
    var front: Front
    var back: Back

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(grab.x, grab.y), AnimatablePair(finger.x, finger.y)) }
        set {
            grab = CGPoint(x: newValue.first.first, y: newValue.first.second)
            finger = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    var body: some View {
        let dx = finger.x - grab.x, dy = finger.y - grab.y
        let d = hypot(dx, dy)
        // No shadow on the top sheet itself: the sheet underneath already casts the pad's shadow, and a
        // shadow on the cut-away stuck part would draw a grey band along the fold.
        if d < 0.5 {
            front
        } else {
            let u = CGVector(dx: dx / d, dy: dy / d)                       // fold normal
            let m = CGPoint(x: (grab.x + finger.x) / 2, y: (grab.y + finger.y) / 2) // point on fold line
            let k = min(1, d / (size * 0.6))                                // how lifted it is
            // Paper doesn't crease when peeled, it rolls. The roll's radius grows as the sheet lifts.
            let r = min(3 + 9 * k, d * 0.2)
            let outer = m - u * r                                           // outermost point of the roll
            let paper = RoundedRectangle(cornerRadius: noteCorner, style: .continuous)

            ZStack(alignment: .topLeading) {
                // Light under the curl: where the roll lifts off, the sheet beneath sits in a soft shade
                // that fades out within a short distance.
                LinearGradient(colors: [.black.opacity(0.06 * k), .black.opacity(0.02 * k), .clear],
                               startPoint: unit(outer), endPoint: unit(outer - u * (8 + 22 * k)))
                    .mask(HalfPlane(point: outer, normal: u, keepPositive: false))
                    .clipShape(paper)
                    .allowsHitTesting(false)

                // Still stuck down.
                front
                    .mask(HalfPlane(point: m, normal: u, keepPositive: true))

                // The roll: the strip of paper curving over. It carries on the flap's tone and only darkens
                // gently toward its outer edge as the surface turns away from the light — no bright bar.
                back
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.035)],
                                       startPoint: unit(m), endPoint: unit(outer))
                    )
                    .clipShape(paper)   // keep shading inside the rounded corners
                    .mask(HalfPlane(point: m, normal: u, keepPositive: false))
                    .mask(HalfPlane(point: outer, normal: u, keepPositive: true))

                // The flap: back of the paper, mirrored across the fold. Paper facing up is lit almost evenly;
                // a faint sheen sits where it bends, and it settles to a hair darker than the front.
                back
                    .overlay(
                        LinearGradient(stops: [
                            .init(color: .white.opacity(0.18), location: 0),
                            .init(color: .clear, location: 0.3),
                            .init(color: .black.opacity(0.025), location: 1),
                        ], startPoint: unit(m), endPoint: unit(m - u * max(d / 2, 1)))
                    )
                    .clipShape(paper)   // without this the gradient's square corner pokes out as a grey tip
                    .mask(HalfPlane(point: m, normal: u, keepPositive: false))
                    .transformEffect(reflection(across: m, normal: u))
                    // Light comes from above, so the lifted flap's shadow falls a little downward, never
                    // sideways along the pull. It is tight and faint at first and softens as the paper rises.
                    .shadow(color: .black.opacity(0.05 + 0.05 * k), radius: 1 + 2 * k, x: 0, y: 1 + k)
                    .shadow(color: .black.opacity(0.04 + 0.06 * k), radius: 4 + 10 * k, x: 0, y: 2 + 8 * k)
            }
            .frame(width: size, height: size)
        }
    }

    private func unit(_ p: CGPoint) -> UnitPoint { UnitPoint(x: p.x / size, y: p.y / size) }

    /// Mirror across the line through `m` with unit normal `u`: P' = P − 2((P − m)·u)u.
    private func reflection(across m: CGPoint, normal u: CGVector) -> CGAffineTransform {
        let c = 2 * (m.x * u.dx + m.y * u.dy)
        return CGAffineTransform(a: 1 - 2 * u.dx * u.dx, b: -2 * u.dx * u.dy,
                                 c: -2 * u.dx * u.dy, d: 1 - 2 * u.dy * u.dy,
                                 tx: c * u.dx, ty: c * u.dy)
    }
}

private func + (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x + v.dx, y: p.y + v.dy) }
private func - (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x - v.dx, y: p.y - v.dy) }
private func * (v: CGVector, s: CGFloat) -> CGVector { CGVector(dx: v.dx * s, dy: v.dy * s) }

/// Everything on one side of a line.
struct HalfPlane: Shape {
    var point: CGPoint
    var normal: CGVector
    var keepPositive: Bool

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 4000
        let n = keepPositive ? normal : CGVector(dx: -normal.dx, dy: -normal.dy)
        let t = CGVector(dx: -n.dy, dy: n.dx)
        return Path { p in
            p.move(to: point + t * big)
            p.addLine(to: point + t * big + n * big)
            p.addLine(to: point - t * big + n * big)
            p.addLine(to: point - t * big)
            p.closeSubpath()
        }
    }
}

// MARK: - Paper

let noteCorner: CGFloat = Radius.lg

/// Front of a note: textured white paper, two binding dots, and the date in ink.
struct NoteFace: View {
    var date: Date?
    var stickers: [PlacedSticker] = []
    var selectedSticker: UUID?
    var landingSticker: UUID?
    var onSelectSticker: ((UUID) -> Void)?

    var body: some View {
        ZStack {
            Group {
                Paper()
                BindingDots()
                if let date { NoteInk(date: date) }
            }
            .accessibilityHidden(true)
            PlacedStickerLayer(stickers: stickers, selected: selectedSticker,
                               landing: landingSticker, onSelect: onSelectSticker)
        }
        .clipShape(RoundedRectangle(cornerRadius: noteCorner, style: .continuous))
    }
}

/// The thickness of the pad under the top sheets: a stack of page edges, each a hair lower and a shade
/// darker, on a firm backing board. Gives the pad the weight of a real desk block.
struct PadBlock: View {
    var size: CGFloat
    /// How many sheet edges show below the top note.
    private let sheets = 7
    /// Vertical step between sheet edges (optical, below the 4pt grid on purpose).
    private let step: CGFloat = 2

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: noteCorner, style: .continuous)
        ZStack {
            // Backing board: slightly warmer and darker, the deepest layer, carrying the main shadow.
            shape.fill(PadColor.board)
                .frame(width: size, height: size)
                .offset(y: step * CGFloat(sheets + 2))
                .padShadow()
            // Sheet edges, deepest first so the upper ones overlap them.
            ForEach((1...sheets).reversed(), id: \.self) { i in
                let t = Double(i) / Double(sheets)
                shape.fill(PadColor.edge.mix(.black, 0.10 * t))
                    .overlay(shape.strokeBorder(Color.black.opacity(0.05 + 0.04 * t), lineWidth: 0.5))
                    .frame(width: size, height: size)
                    .offset(y: step * CGFloat(i))
            }
        }
    }
}

/// Back of a note: the same paper a shade darker, with the ink faintly showing through.
struct NoteBack: View {
    var date: Date

    var body: some View {
        ZStack {
            Paper()
            Color.black.opacity(0.035)
            NoteInk(date: date).opacity(0.06)
        }
        .clipShape(RoundedRectangle(cornerRadius: noteCorner, style: .continuous))
    }
}

/// The photographed paper texture, brightened toward white.
private struct Paper: View {
    var body: some View {
        ZStack {
            // Overlay on a flexible base so the photo is cropped to the note, not sizing it.
            Color.white.overlay {
                Image("PaperTexture")
                    .resizable()
                    .scaledToFill()
            }
            Color.white.opacity(0.45)
            // Soft light falling across the sheet.
            LinearGradient(colors: [.white.opacity(0.25), .clear, .black.opacity(0.025)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipped()
    }
}

/// Two small dots along the top, like the punched binding of a desk pad.
private struct BindingDots: View {
    var body: some View {
        HStack(spacing: 120) {
            ForEach(0..<2, id: \.self) { _ in
                Circle()
                    .fill(Color.black.opacity(0.12))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .frame(width: Space.sm, height: Space.sm)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, Space.sm)
    }
}

/// Thin wire loops through the two binding holes, curling over the top edge and behind the pad.
/// Drawn as a small cylinder (dark edge, lighter core, bright specular line) with a soft contact shadow.
private struct RingBinding: View {
    var size: CGFloat

    // Must match `BindingDots`: two holes, 120 apart, centred 18 below the top edge.
    private let holeSpacing: CGFloat = 120 + Space.sm
    private let holeY: CGFloat = Space.sm + Space.sm / 2
    private let spec = RingWire.Spec.pad

    var body: some View {
        let pad: CGFloat = spec.rise + 8
        Canvas { ctx, canvas in
            let top = pad                      // paper's top edge in canvas space
            for cx in [canvas.width / 2 - holeSpacing / 2, canvas.width / 2 + holeSpacing / 2] {
                RingWire.draw(in: ctx, hole: CGPoint(x: cx, y: top + holeY), top: top, spec: spec)
            }
        }
        .frame(width: size, height: size + pad)
        .offset(y: -pad / 2)
    }
}

private struct NoteInk: View {
    var date: Date
    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.day()))
                .font(Typeface.numeral)
                .foregroundStyle(Ink.text.opacity(0.88))
                .padding(.vertical, -10)
            Text(date.formatted(.dateTime.weekday(.wide)).lowercased())
                .font(Typeface.noteTail)
                .foregroundStyle(Ink.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Short month written along the binding, centred between the two ring holes.
        .overlay(alignment: .top) {
            Text(date.formatted(.dateTime.month(.wide)).lowercased())
                .font(Typeface.noteLead)
                .foregroundStyle(Ink.text.opacity(0.7))
                .frame(height: Space.sm * 3)
                .padding(.top, Space.md)                      // sits just below the ring holes, centred between them
        }
    }
}

extension View {
    /// Paper resting on paper: tight contact shadow plus a soft ambient one.
    func paperShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    /// The whole pad resting on the desk: a tight contact shadow and a wide, soft one for its weight.
    func padShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 2, x: 0, y: 2)
            .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 16)
    }
    /// Lighter shadow for the sheets lower in the pad.
    func softSheetShadow() -> some View {
        shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}
