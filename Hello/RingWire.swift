import SwiftUI

/// A metal binding ring, shared by the app's pad and the home-screen widget.
///
/// Seen slightly from above, a ring is a curved loop: the front strand bows outward as it rises
/// out of the hole, rolls over the top, and the back strand curves down behind the pad.
enum RingWire {
    struct Spec {
        var rise: CGFloat      // how far the loop stands above the paper
        var width: CGFloat     // front strand to back strand
        var wire: CGFloat      // wire thickness

        static let pad = Spec(rise: 16, width: 12, wire: 2.4)
        static let widget = Spec(rise: 10, width: 8, wire: 1.6)
    }

    /// Draws one ring whose front strand enters the paper at `hole`; `top` is the paper's top edge.
    static func draw(in ctx: GraphicsContext, hole: CGPoint, top: CGFloat, spec: Spec) {
        let (front, back) = paths(hole: hole, top: top, spec: spec)
        let w = spec.wire

        // Contact shadow on the paper and on the pad behind.
        var shadow = ctx
        shadow.addFilter(.blur(radius: w * 0.7))
        shadow.translateBy(x: w * 0.5, y: w * 0.85)
        shadow.stroke(front, with: .color(.black.opacity(0.16)), style: StrokeStyle(lineWidth: w, lineCap: .round))
        shadow.stroke(back, with: .color(.black.opacity(0.08)), style: StrokeStyle(lineWidth: w, lineCap: .round))

        // The back strand sits in shade, so it is a little darker; it's cut clean where it passes behind the edge.
        cylinder(back, in: ctx, wire: w, base: 0.50, core: 0.68, shine: 0.45, cap: .butt)
        cylinder(front, in: ctx, wire: w, base: 0.56, core: 0.78, shine: 0.9, cap: .round)

        // A dark rim where the wire enters the hole.
        ctx.fill(Path(ellipseIn: CGRect(x: hole.x - w * 1.1, y: hole.y - w * 0.6, width: w * 2.2, height: w * 1.2)),
                 with: .color(.black.opacity(0.22)))
    }

    /// Front: one continuous curve from the hole, over the top and partway down the back (no seam at the top).
    /// Back: the rest of the way down, ending at the paper's top edge.
    static func paths(hole a: CGPoint, top: CGFloat, spec: Spec) -> (front: Path, back: Path) {
        let w = spec.width, rise = spec.rise
        let apex = top - rise
        let h = a.y - apex
        let crown = CGPoint(x: a.x + w * 0.5, y: apex)
        let p = CGPoint(x: a.x + w * 1.02, y: top - rise * 0.4)
        let edge = CGPoint(x: a.x + w * 0.96, y: top - 0.5)

        var front = Path()
        front.move(to: a)
        // Bows out to the left as it rises, then rolls over the crown.
        front.addCurve(to: crown,
                       control1: CGPoint(x: a.x - w * 0.6, y: a.y - h * 0.4),
                       control2: CGPoint(x: a.x - w * 0.1, y: apex))
        front.addCurve(to: p,
                       control1: CGPoint(x: a.x + w * 1.1, y: apex),
                       control2: CGPoint(x: a.x + w * 1.08, y: p.y - rise * 0.3))

        var back = Path()
        back.move(to: p)
        back.addQuadCurve(to: edge, control: CGPoint(x: a.x + w * 1.04, y: top - rise * 0.15))
        return (front, back)
    }

    /// Fakes a round wire: dark outline, lighter core, then a thin highlight nudged toward the light.
    private static func cylinder(_ path: Path, in ctx: GraphicsContext, wire: CGFloat,
                                 base: Double, core: Double, shine: Double, cap: CGLineCap) {
        ctx.stroke(path, with: .color(Color(white: base)), style: StrokeStyle(lineWidth: wire, lineCap: cap, lineJoin: .round))
        ctx.stroke(path, with: .color(Color(white: core)), style: StrokeStyle(lineWidth: wire * 0.55, lineCap: cap, lineJoin: .round))
        var hi = ctx
        hi.translateBy(x: -wire * 0.15, y: -wire * 0.15)
        hi.stroke(path, with: .color(.white.opacity(shine)), style: StrokeStyle(lineWidth: wire * 0.22, lineCap: cap, lineJoin: .round))
    }
}
