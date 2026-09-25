# Emojichao Keyboard (iOS, Phase 1 — add-on keyboard, local search only)

This is the mobile counterpart discussed for Emojichao: not a full keyboard
replacement (Simeji-style), but an **add-on keyboard** you switch to with the
globe key. Unlike the macOS app's ':shortcode' trigger, this keyboard
searches by whatever word you're currently typing, no explicit trigger
needed — the same way apps like "Emojo" work. It reuses the exact
catalog/scoring logic from the macOS app via the
`EmojiCatalogCore` Swift package (see `EmojiCatalogCore/`, at the repo root —
kept as its own standalone package, separate from this repo's root
`Package.swift`, specifically so it has no AppKit-only targets in its
manifest and Xcode can resolve it cleanly for an iOS target).

**This code has not been built or run.** The session that wrote it runs in a
Linux container with no Swift toolchain, no Xcode, and no iOS SDK — there is
no way to compile-check or simulator-test it there. Everything below has been
written carefully against the real iOS APIs, but you should expect to fix a
few small mistakes the first time you build it in Xcode.

## What's here

- `EmojichaoKeyboard/KeyboardViewController.swift` — the `UIInputViewController`
  subclass: draws a minimal single-layout QWERTY (no shift, no symbols page,
  no autocorrect), tracks the word currently being typed since the last word
  boundary (space, return, punctuation), and shows matches in a candidate
  strip above the keys — updated on every keystroke, no ':' needed. Tapping
  a candidate deletes the typed word and inserts the emoji in its place.
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
3. **Add the `EmojiCatalogCore` folder itself as a local Swift Package
   dependency** — File → Add Package Dependencies → Add Local... → select
   `EmojiCatalogCore/` at the repo root (the folder that directly contains
   *its own* `Package.swift`; not the repo root itself, and not
   `AppSources/`). Link the `EmojiCatalogCore` library product to **both**
   the container app target and the keyboard extension target (General tab →
   "Frameworks, Libraries, and Embedded Content" → "+" → search
   "EmojiCatalogCore").
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

- No shift/caps, symbols page, or autocorrect. Search words are typically
  short romaji/English fragments (mirroring the macOS app's text-search mode),
  so a plain lowercase layout covers the core use case.
- Because there's no explicit trigger, the candidate strip updates on every
  keystroke of the current word — this is closer to the "noisy" built-in IME
  emoji suggestions discussed earlier than the macOS app's on-demand ':'
  search. If that turns out to be too eager in practice, an explicit trigger
  is easy to bring back.
- No remote (Jev) semantic ranking — everything is `EmojiCatalog.localMatches`,
  matching the "local-only first" design discussed for privacy and to avoid
  the iOS "Allow Full Access" prompt entirely in this phase.
- No App Group / shared catalog storage yet. `EmojiCatalog` falls back to the
  bundled `emoji-catalog-curated.json` resource shipped inside the
  `EmojiCatalogCore` package, so it works standalone without extra setup.
