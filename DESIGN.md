# Finance buddy — design language

One design language across every screen. When adding UI, use these pieces
instead of inventing new ones. Everything referenced here lives in
`App/Theme.swift` and `Views/AddItemOverlays.swift`.

## Palette (adaptive monochrome)

Every `fb*` colour resolves per colour scheme (`Color(light:dark:)`), so
the mono palette inverts cleanly. The user picks System/Light/Dark in
Profile (`FBAppearance` via `@AppStorage("fbAppearance")`, applied with
`preferredColorScheme` at the root). Never use raw `Color.white`/`.black`
for functional fills — use `fbInk` opacities so they adapt.


| Token | Role |
| --- | --- |
| `fbBackground` | Near-black app background (`FBBackground` adds the top glow) |
| `fbCard` | Card surface (use the `Card` container, not the raw colour) |
| `fbInk` | Primary text, hero numbers, "pending" bar segments |
| `fbSoftText` | Secondary text |
| `fbHairline` | Dividers and borders |
| `fbPositive` | Accent (white in the mono scheme) — primary buttons, safe-to-spend |
| `fbWarning` | The one non-mono tone (muted terracotta) — overspend, destructive |
| `fbCommitment` | Mid grey — user chat bubble; at 30 % opacity, "paid" bar segments |

Safe-to-spend is always **striped** (`StripedFill`), never solid. Paid =
faded grey, pending = white, safe = stripes.

## Typography

- `fbHeader` — bold rounded headers, negative tracking applied on the Text.
- `fbNumber` — monospaced for every financial figure.
- `fbBody` — everything else.

## Modals

Never `.sheet()`, `.alert()` or system chrome. A modal is:

1. `ModalBackdrop` — ultra-thin material + black 35 % dim. Tapping it
   dismisses only the frontmost layer.
2. `ModalCard` — a bottom-anchored floating card.
3. Stacking happens on the **z-axis**: when a form opens from a list, the
   list card recedes (`ModalCard(depth: 1)` — scales down, dims, blurs)
   and the form arrives with `.fbModalPush` + `.fbModal` spring. Same
   pattern everywhere: payments, income, categories, quick add.
4. Modals are presented at the **root**, never inside a page. Screens
   request one via their `present: (AppModal) -> Void` callback;
   `ContentView` renders it in an `.overlay` applied *after*
   `.safeAreaBar`, which guarantees the modal draws on top of the tab bar
   (an overlay inside a page always draws underneath the bar). The bar
   itself stays put — the backdrop dims it with the rest of the screen;
   sliding it out looked glitchy. New modals get a case in `AppModal`.
5. Tapping any non-interactive part of a modal card dismisses the
   keyboard (`fbDismissKeyboard()` in `ModalCard`) — required because the
   decimal pad has no return key.
6. Modal forms keep **non-optional draft state behind a `showForm` Bool**.
   Never model "form open" as an optional draft unwrapped with
   `Binding($draft)` — that traps when the draft goes nil while the card
   is still animating out.
7. Date fields use `FBDateField` ("30 July 2026", unfolding calendar) —
   never the compact `DatePicker`, whose format is inconsistent.

## Buttons

- **Vertical stacks only.** Primary on top (`FBPrimaryButton`, filled),
  secondary below (`FBSecondaryButton`, quiet). Never side-by-side.
- Disabled state is **opacity only** (dimmed, same fill) — never a
  different fill colour.
- Destructive primaries use `destructive: true` (terracotta), and
  destructive entry points (e.g. Sign out) are quiet text, not banners.
- Every tappable control uses `.buttonStyle(.pressable)`.

## Forms

- `LabeledField` + `PlainTextField` / `CurrencyField` / `CurrencyEntryField`.
- Recurring vs one-off is a **switch** (`FBToggleRow(label: "Recurring")`)
  inside the form — never tabs/segments, and never a day-number picker:
  recurring items pick a date with `FBDateField` and repeat monthly on
  that day.
- Amount fields carry calculator ops (+ − × ÷ =) on the keyboard itself
  (`amountKeyboardOps`) — never as chrome in the form UI.
- There is no standalone "payday" input: payday is derived from recurring
  income dates (`Finances.nextPayday()`).
- Item lists in modals use `ModalItemRow` (tap to edit, trailing minus to
  delete) and `ModalEmptyHint`.

## Motion

- `.fbModal` spring for modal layers and layout moves.
- `.contentTransition(.numericText(...))` for changing money.
- Scroll edges use the standard iOS soft edge effect
  (`.scrollEdgeEffectStyle(.soft, for: .vertical)`), no custom masks.

## Input

The Ask tab uses one input pill: the text field is the default, with the
mic **inside the field** (trailing) to trigger dictation, quick-add (+)
to the field's left, and a send button that only exists while there's
text to send — no visible disabled state. Assistant replies are plain
text (no bubble); only the user's messages get a bubble.

## Modal surfaces

Modal cards are **opaque** (`Card(opaque: true)`) — glass bleed under
dimmed controls reads as broken. Page cards stay glassy.
