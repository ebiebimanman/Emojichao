# Emojichao Keyboard (iOS, Phase 1 — add-on keyboard, local search only)

This is the mobile counterpart discussed for Emojichao: not a full keyboard
replacement (Simeji-style), but an **add-on keyboard** you switch to with the
globe key just to search emoji by shortcode, the same way apps like "Emojo"
work. It reuses the exact catalog/scoring logic from the macOS app via the
new `EmojiCatalogCore` Swift package target (see `AppSources/EmojiCatalogCore`).

**This code has not been built or run.** The session that wrote it runs in a
Linux container with no Swift toolchain, no Xcode, and no iOS SDK — there is
no way to compile-check or simulator-test it there. Everything below has been
written carefully against the real iOS APIs, but you should expect to fix a
few small mistakes the first time you build it in Xcode.

## What's here

- `EmojichaoKeyboard/KeyboardViewController.swift` — the `UIInputViewController`
  subclass: draws a minimal single-layout QWERTY (no shift, no symbols page,
  no autocorrect — just enough to type a `:shortcode` query), tracks the
  `:query` buffer the same way the macOS app's text-search mode does, and
  shows matches in a candidate strip above the keys.
- `EmojichaoKeyboard/EmojiCandidateStripView.swift` — the horizontally
  scrolling row of tappable emoji candidates, drawn by the extension itself
  (neither iOS nor Android give third-party keyboards a way to inject into
  the system's own predictive-text bar — see the design discussion in this
  repo's history for why every third-party keyboard, including this one,
  draws its own strip).

Both files import `EmojiCatalogCore` for `EmojiCatalog.shared.localMatches(_:)`
and `EmojiSearchPolicy.isSearchableCharacter(_:)` — the same matching and
shortcode-character rules the macOS app uses, unchanged.

## What you'll need to do in Xcode

1. **Create a new iOS App project** (File → New → Project → App). This becomes
   the container app — mostly a shell with onboarding text telling the user
   how to enable the keyboard.
2. **Add a Custom Keyboard Extension target** (File → New → Target → Custom
   Keyboard Extension) to that project.
3. **Add this repository as a local Swift Package dependency** (File → Add
   Package Dependencies → Add Local... → select the Emojichao repo root,
   which contains `Package.swift`). Link the `EmojiCatalogCore` library
   product to **both** the container app target and the keyboard extension
   target.
4. Delete the extension template's placeholder `KeyboardViewController.swift`
   and add the two files from `ios/EmojichaoKeyboard/` in its place (drag them
   into the extension target, making sure "Copy items if needed" is checked
   and the target membership is set to the keyboard extension only).
5. In the extension's `Info.plist`, confirm under `NSExtension` →
   `NSExtensionAttributes`:
   - `RequestsOpenAccess` is `NO` — this build makes no network calls, so it
     should never need to ask for "Allow Full Access."
   - `IsASCIICapable` can stay `YES` since the layout is a plain QWERTY.
6. Build and run the extension target, then in the Simulator/device go to
   Settings → General → Keyboard → Keyboards → Add New Keyboard... and enable
   "Emojichao Keyboard". Switch to it from any text field via the globe key.

## Known simplifications (by design, for this first pass)

- No shift/caps, symbols page, or autocorrect. Shortcode queries are typically
  short romaji/English fragments (mirroring the macOS app's text-search mode),
  so a plain lowercase layout covers the core use case.
- No remote (Jev) semantic ranking — everything is `EmojiCatalog.localMatches`,
  matching the "local-only first" design discussed for privacy and to avoid
  the iOS "Allow Full Access" prompt entirely in this phase.
- No App Group / shared catalog storage yet. `EmojiCatalog` falls back to the
  bundled `emoji-catalog-curated.json` resource shipped inside the
  `EmojiCatalogCore` package, so it works standalone without extra setup.
