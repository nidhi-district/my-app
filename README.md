# StillDay — Design Rules

StillDay is a calm, paper-like day planner. Every screen must feel quiet, editorial and deliberate.
These rules are binding: any new view or change must follow them. All tokens live in
[`Hello/Theme.swift`](Hello/Theme.swift). **Never hard-code a font, colour, spacing, radius or size in a view.**

---

## 1. Typography

### Everything is lowercase

**All text in the app and the widget is lowercase**: headings, labels, buttons, dates, event titles,
places, hints. No capitals, no uppercase eyebrows, no title case. It is enforced at the root with
`.textCase(.lowercase)` on `TodayScreen` and on the widget's view, so it applies to every `Text`, including
user data such as event titles. Do not remove it, and do not add any view that bypasses it.

### Typefaces

StillDay pairs handwritten dates with a sans-serif interface.

| Role | Family | Use for |
|---|---|---|
| Display | **Cormorant Garamond** (bundled) | Light day numerals, medium year labels and semibold month titles. |
| Handwritten labels | **Bradley Hand** (system) | The day header and the month and weekday on the paper. |
| Interface | **Poppins** (bundled) | Calendar tabs, week and year views, sticker controls and labels. |

Bundled fonts are registered at launch by `Typeface.registerBundledFonts()` (called from `HelloApp.init`
and the widget bundle), so no Info.plist entry is needed. Refer to fonts only through `Typeface`.

### Type scale (`Typeface`)

| Token | Font | Size | Where |
|---|---|---|---|
| `numeral` / `numeral(size:)` | Cormorant Garamond Light, lining figures | 156 on the note | Day number on the note, calendar thumbnails and widget |
| `monthTitle` / `yearHeading` / `yearCaption` / `yearTabLabel` | Cormorant Garamond Semibold / Medium | 68 / 24 / 21 / 18, scales | Month titles, year headings and the year tab label |
| `dateHeading` | Bradley Hand Bold | 23, scales | Date above the note |
| `noteLead` / `noteTail` | Bradley Hand Bold | 20 / 26, fixed | Month and weekday on the note |
| `paperLabel(_:)` | Bradley Hand Bold | Fixed per layout | Month and weekday on the widget |
| `heading` / `calendarTitle` | Poppins Medium | 17 / 22, scales | Drawer and calendar titles |
| `body` / `subhead` / `caption` | Poppins Regular | 15 / 14 / 12, scales | Interface text |
| `callout` / `tabLabel` | Poppins Medium | 14 / 12, scales | Readouts and tab labels |
| `icon` / `iconSmall` / `tabIcon` | System symbol font | 15 / 12 / 18 medium | SF Symbols |

Rules:
- **No italics.** All type is upright; secondary information is distinguished by size and `Ink.muted`, not slant.
- Use `.monospacedDigit()` (via `callout`) for numeric readouts.
- Maximum two weights on one screen region. Prefer regular; emphasis comes from size and colour, not bold.
- Text printed *on* the fixed-size note uses fixed sizes; everything else should respect Dynamic Type.

## 2. Spacing — 4pt grid (`Space`)

Every margin, padding and gap is a multiple of 4.

| Token | Value | Use |
|---|---|---|
| `xxs` | 4 | Icon ↔ label, title ↔ subtitle |
| `xs` | 8 | Between list rows, small gaps |
| `sm` | 12 | Vertical padding inside rows, compact elements |
| `md` | 16 | Standard inner padding |
| `margin` | 20 | **Screen side margin** — content never comes closer to the edge |
| `lg` | 24 | Between sections |
| `xl` | 32 | Large separations |
| `xxl` | 48 | Bottom of a scroll view |

Rules:
- Related items sit closer than unrelated ones (proximity): inside a group ≤ `xs`, between groups ≥ `lg`.
- Side margin is always `Space.margin`; nothing is full-bleed except backgrounds.
- No odd numbers (2, 6, 10, 13, 18, 22…). Allowed exceptions: 1pt hairlines and optical tweaks for display type, each with a comment.

## 3. Sizes (`Size`)

- Every tappable element is at least **44 × 44pt** (`Size.tapTarget`, Apple HIG).
- Rows use `minHeight` plus vertical padding so text can grow.
- The note is `min(340, screen width − 2 × margin)` so it fits every iPhone.
- The grabber pill is Apple's standard 36 × 5.

## 4. Corner radius (`Radius`)

| Token | Value | Use |
|---|---|---|
| `sm` | 12 | Small chips, inputs |
| `md` | 16 | Rows, cards |
| `lg` | 24 | The sticky note, large surfaces |

Always use `style: .continuous` (squircle). Nested shapes: inner radius = outer radius − padding.

## 5. Colour (`Ink`, `AgendaTint`)

- Background: `Ink.canvas`, a barely-warm white. Text: `Ink.text`. Secondary: `Ink.muted`.
- Dividers: `Ink.hairline`, 1pt.
- Sticker previews use the pale fills in `CraftTint`.
- No pure black text, no saturated colours, no gradients except the paper's lighting.

## 6. Elevation & material

- Paper sits on paper: `paperShadow()` for the top note, `softSheetShadow()` for sheets beneath, and
  `padShadow()` for the pad as a whole resting on the desk. No other shadows.
- The pad has real thickness (`PadBlock`): stacked sheet edges 2pt apart (an optical exception to the 4pt
  grid), each a shade darker, on a warm backing board (`PadColor`).
- Peeled paper **rolls**, it never creases: the fold is drawn as a shaded curl, and every shading layer on
  the paper is clipped to the note's rounded corners so no square corner ever shows.
- Shadows while peeling follow one light, from above: the lifted flap's shadow falls slightly **downward**,
  never sideways along the pull, and starts tight and faint, softening as the paper rises. The flap is lit
  almost evenly (a faint sheen at the bend only), and the curl darkens only gently toward its edge. The top
  sheet casts no shadow of its own while peeling; the sheet beneath already carries the pad's shadow.
- Floating controls use `.glass(...)`. The bottom tab bar uses clear, untinted glass and an inset translucent lens. Header controls use a light paper tint. Older systems use frosted material, and Reduce Transparency uses solid surfaces.
- The Year header matches the paper at rest and uses a single, feathered layer of translucent blur as the calendar scrolls behind it.

## 7. Motion

- Natural and physical: springs for snap-back, ease curves for throws. Nothing bounces for decoration.
- Text that changes uses `contentTransition` (`.opacity` for words, `.numericText()` for numbers), about 0.35s.
- Pair meaningful motion with light haptics.
- Calendar tab changes crossfade with a short rise and a sliding glass selection indicator. Reduce Motion uses a crossfade alone.
- On iOS 18 and later, a downward finger swipe contracts the floating tab bar and an upward finger swipe starts expanding it immediately. Labels also return after a short pause. The calendar scrolls behind the translucent bottom gradient, with fixed scroll clearance for the bar.
- **The paper is in the user's hand.** Swipe up or left for the next day, and down or right for the previous day.
  The sheet follows the finger and can be held mid-peel. A long pull or a short flick turns one page, and a
  short pull settles back down. The sheet exits in the direction of the turn.
- Sound is subtle and physical (`PaperSound`, synthesised, ambient session — silent when the ringer is off):
  a continuous paper rustle while the sheet is handled, its loudness following finger speed and going quiet
  when held still; a peel crackle when it tears; a soft whoosh as it flies.

## 8. Checklist before merging a UI change

- [ ] All text is lowercase (root `.textCase(.lowercase)` intact; no capitals in new strings either).
- [ ] Text uses Poppins for controls, Bradley Hand for handwritten labels and Cormorant Garamond for numerals and Year display type via `Typeface`.
- [ ] Every spacing value is a `Space` token.
- [ ] Tap targets ≥ 44pt.
- [ ] Fits a 375pt-wide screen with 20pt margins.
- [ ] Colours come from `Ink` / `CraftTint`.
- [ ] Builds without warnings.

---

### Project

SwiftUI, iOS 17+. The project is generated with XcodeGen — after adding files run `xcodegen generate`.
