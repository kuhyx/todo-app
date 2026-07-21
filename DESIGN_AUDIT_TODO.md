# Design audit — todo

Generated against safe-design-rules (anthonyhobday.com/sideprojects/saferules).
Report only — nothing in this repo was changed by the audit itself.

## Flutter app (lib/)

Theme entry point: `lib/main.dart:36-39` — a single inline `ThemeData` with
`ColorScheme.fromSeed(seedColor: Colors.deepPurple)` and `useMaterial3: true`.
No dedicated theme file, no `darkTheme`, no `textTheme`/component-theme
overrides, no custom shadows or corner radii anywhere in `lib/` (confirmed by
grepping for `BoxShadow`, `elevation`, `BorderRadius`, `Card(` — zero hits
outside framework defaults). This means almost every token rule is satisfied
*by deferring to Material 3's generated palette/type scale*, which is itself a
coherent, deliberately-designed system — that counts as Pass, not as an
absence-of-system finding (contrast the web/Tkinter case where hardcoded
per-file values have no source of truth at all).

### Violations

- **Rule 4 (everything deliberate) / color consistency** — `lib/ui/settings_screen.dart:410` —
  `Text(_error!, style: const TextStyle(color: Colors.red))` hardcodes a raw
  `Colors.red` instead of the theme's error color. Every other error-state
  text in the app uses `theme.colorScheme.error`
  (`lib/ui/capture_screen.dart:522`, `lib/ui/notes_list_screen.dart:375`) —
  this is the one place that breaks the pattern → change to
  `Theme.of(context).colorScheme.error`.
- **Rule 11 (mathematically related measurements)** — the app's spacing is
  overwhelmingly on a 4px scale (4/8/12/16/20/24/96 all appear repeatedly),
  but a few values break it: `SizedBox(height: 6)` at
  `lib/ui/notes_list_screen.dart:411,574,646`; `SizedBox(height: 10)` at
  `lib/ui/markdown_view.dart:29`; `EdgeInsets.only(top: 8, bottom: 2)` /
  `EdgeInsets.only(bottom: 4)` / `EdgeInsets.only(left: 4, top: 2)` at
  `lib/ui/markdown_view.dart:35,49,78` (the `2`s). Round these to the nearest
  4px step (6→8, 10→8 or 12, 2→4) for consistency.
- **Rule 21 (line length ~70 chars)** — `lib/ui/markdown_view.dart` (the
  rendered-note view) and the raw-mode `TextField` in
  `lib/ui/note_editor.dart:520-535` have no max-width constraint; both sit
  directly in a `SingleChildScrollView`/`Expanded` that fills the available
  width. Per this repo's own `CLAUDE.md`, the desktop build is a Chrome
  `--app` window (potentially 4K), so body text lines run the full window
  width, far past the 60-80 char readable range. Constrain text columns with
  a `ConstrainedBox(maxWidth: ~640)` (or similar) centered in the available
  space on wide viewports; mobile widths are already narrow enough to be fine.

### Pass (defers to Material 3 defaults from `main.dart:36-39`, or otherwise verified)

- **Rule 1** (near-black/near-white) — M3's generated tonal palette, not pure black/white.
- **Rule 2** (saturate neutrals) — M3's seed-derived neutrals carry the seed hue.
- **Rule 3** (high contrast for important elements) — `FilledButton`/`IconButton` get M3's on-primary contrast automatically.
- **Rule 6** (letter-spacing/line-height by size) — M3 `TextTheme` scale.
- **Rule 7** (container border contrast) — `OutlineInputBorder()` used throughout (e.g. `lib/ui/settings_screen.dart:244,252,268,278`) resolves via theme, no custom borders.
- **Rule 8** (align with something else) — screen-level body padding is a consistent `EdgeInsets.all(16)` across `lib/ui/capture_screen.dart:451`, `lib/ui/note_detail_screen.dart:67`, `lib/ui/settings_screen.dart:221`.
- **Rule 9** (distinct brightness per palette color) — M3 tonal palette assigns each role a distinct tone.
- **Rule 10** (warm OR cool, not both) — single seed color (`Colors.deepPurple`) drives the whole palette.
- **Rule 14** (space between high-contrast points) — standard Material component spacing, no bounding-box vs. visual-edge mismatches found.
- **Rule 17** (simple on complex) — all surfaces are plain `Scaffold`/`ListView` backgrounds, no background imagery/texture.
- **Rule 19** (outer padding ≥ inner padding) — e.g. `lib/ui/settings_screen.dart:318-331` (Export/Import button row: 12px gap between buttons) sits inside the screen's 16px outer padding; same pattern in `capture_screen.dart`'s priority/status row (12px gap inside 16px body padding).
- **Rule 20** (body text ≥16px) — `bodyLarge` (16px, M3 default) is used for all primary editable/read text (`lib/ui/note_editor.dart:528`, `lib/ui/markdown_view.dart:82-95`); `bodySmall` (12px) is reserved for secondary captions/timestamps only (`lib/ui/capture_screen.dart:511`, `lib/ui/settings_screen.dart:231`), which is the sanctioned M3 caption use, not body text.
- **Rule 22** (button padding horizontal = 2x vertical) — no custom `ButtonStyle` padding overrides found; `FilledButton`/`OutlinedButton` use M3 defaults, which follow this ratio.
- **Rule 23** (two typefaces max) — single default Material/Roboto family; `pubspec.yaml` declares no custom fonts, no `google_fonts` dependency.
- **Rule 25** (avoid adjacent hard divides) — the one `Divider` in the list (`lib/ui/notes_list_screen.dart:232`, `height: 1`) separates list rows only, no stacked borders; the settings-screen `Divider()` (`lib/ui/settings_screen.dart:308`) has 8-24px spacing on both sides, not adjacent to another edge.
- **Rule 27** (don't mix depth techniques) — no custom shadow/elevation overrides anywhere in `lib/`; consistent flat M3 default depth throughout.
- **Rule 28** (icon contrast vs. text) — icons use the default M3 `IconTheme` (tied to `onSurfaceVariant`-class roles), no hardcoded full-contrast icon colors placed next to text were found.

### Not applicable

- **Rule 5** (optical alignment) — no custom-drawn shapes/icons with off-center mass; all icons are stock `Icons.*` glyphs, whose optical centering Material already handles.
- **Rule 12** (order by visual weight) — standard `AppBar` + list/form layouts, not a composition with deliberately varied visual weights to order.
- **Rule 13** (12-column grid) — single-column mobile/narrow-desktop layouts throughout; no multi-column grid exists to check.
- **Rule 15** (closer elements lighter, light+dark) — no custom z-stacked/elevated surfaces with tuned lightness, and no `darkTheme` exists to check the dark-mode half of this rule.
- **Rule 16** (shadow blur ≈ 2x distance) — zero custom `BoxShadow` usage in the codebase (confirmed by grep); nothing to check.
- **Rule 18** (container brightness limits, light/dark) — no custom nested-container brightness steps defined; M3 default surface tones apply, and there is no dark theme to check the 12%-dark-interface half.
- **Rule 24** (nest corners properly) — no custom corner radii anywhere; all components use M3 default shapes.
- **Rule 26** (no shadows in dark interfaces) — no dark theme exists, and no shadows exist in light mode either, so this rule has nothing to trigger on.

### Notes

- No dedicated theme file exists (`ThemeData` is inline in `lib/main.dart`,
  32 `.dart` files total) — this is fine at the current size but worth
  extracting to `lib/ui/theme.dart` if the theme grows beyond the current
  3-line `ThemeData(...)`.
- No `darkTheme` is provided. The 28 rules don't mandate one, so its absence
  is not a violation — but if a dark theme is added later, re-check rules 15,
  18, and 26 (shadow/lightness/brightness-limit rules only bite once a dark
  surface exists).
- The single hardcoded-color violation (`Colors.red`) is also the app's only
  spot where a raw `Colors.*` constant appears outside `main.dart`'s seed —
  fixing it removes the last non-theme-derived color reference in the app.
