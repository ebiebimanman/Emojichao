# Emojichao Keyboard (iOS)

An add-on keyboard (switch to it with the globe key, same as Gboard/Simeji)
that searches emoji by the word you're currently typing — no explicit
trigger needed. Typing is **romaji-to-hiragana only** (no Latin/English
mode, no kanji conversion — see "Known limitations" below). It reuses the
exact catalog/scoring/Jev logic from the macOS app via the `EmojiCatalogCore`
Swift package (`EmojiCatalogCore/` at the repo root — kept as its own
standalone package, separate from this repo's root `Package.swift`,
specifically so it has no AppKit-only targets in its manifest and Xcode can
resolve it cleanly for an iOS target).

**This code has not been built or run** by whoever/whatever wrote it — no
Swift toolchain was available. Written carefully against the real iOS APIs,
but expect a few small mistakes on first build.

## What's here

- `EmojichaoKeyboard/KeyboardViewController.swift` — the `UIInputViewController`
  subclass: draws a lowercase QWERTY-shaped key layout, converts typed
  romaji to hiragana as you go, tracks the word being typed since the last
  boundary (space/return/punctuation), and shows matches in a candidate
  strip above the keys, updated on every keystroke. Tapping a candidate
  deletes the typed word and inserts the emoji in its place. Extension-only
  (add to the keyboard extension target).
- `EmojichaoKeyboard/EmojiCandidateStripView.swift` — the horizontally
  scrolling row of tappable emoji candidates, drawn by the extension itself
  (neither iOS nor Android give third-party keyboards a way to inject into
  the system's own predictive-text bar). Extension-only.
- `EmojichaoKeyboard/RomajiConverter.swift` — the romaji→hiragana table and
  incremental conversion logic (handles きゃ/しゃ-style combos, っ via
  doubled consonants, ん). Extension-only.
- `EmojichaoShared/JevKeyStore.swift` — reads/writes the Jev API key in an
  App Group–shared `UserDefaults`, so the container app (where it's typed
  in) and the extension (where it's used) can both reach it. **Add this one
  file to BOTH targets.**
- `EmojichaoApp/ContentView.swift` — a drop-in replacement for the container
  app template's `ContentView.swift`: onboarding text plus the Jev API key
  field. Container-app-only.

## Xcode setup

1. **Create a new iOS App project**, then **add a Custom Keyboard Extension
   target** to it (File → New → Target). This part hasn't changed if you
   already did it before.
2. **Add `EmojiCatalogCore/` as a local Swift Package dependency** (File →
   Add Package Dependencies → Add Local... → select the `EmojiCatalogCore`
   folder at the repo root — the one that directly contains *its own*
   `Package.swift`). When the target-picker sheet appears right after
   adding, check **both** the container app and the extension. (If it
   doesn't show up there, see the note below.)
3. **Add the files**, matching each to the target noted above:
   - `EmojichaoKeyboard/*.swift` → keyboard extension target only
   - `EmojichaoShared/JevKeyStore.swift` → **both** targets
   - `EmojichaoApp/ContentView.swift` → replaces the container app's
     existing `ContentView.swift` (same struct name, so nothing else needs
     rewiring)
4. **Add the "App Groups" capability** to both targets (select the target →
   Signing & Capabilities → + Capability → App Groups), and add the same
   group ID to both — e.g. `group.com.emojichao.shared`. If you use a
   different ID than that, update `JevKeyStore.appGroupID` to match.
5. **Set the extension's `RequestsOpenAccess` to `YES`** in its `Info.plist`
   (`NSExtension` → `NSExtensionAttributes`). This is required for any
   network call (Jev), but the user still separately chooses whether to
   grant it in Settings — declaring it here doesn't force it on.
6. Build and run, enable the keyboard in Settings → General → Keyboard →
   Keyboards → Add New Keyboard, and try it in any text field via the globe
   key.
7. To use Jev: open the container app, paste in a Jev API key, save. Then in
   Settings → Keyboard → Keyboards → Emojichao Keyboard, turn on "Allow Full
   Access". Without either of those, the keyboard still works — it just
   stays local-only, same as before.

If a freshly added local package doesn't show up when linking it to a
target ("Frameworks, Libraries, and Embedded Content" → "+"), that's a
separate Xcode/package-resolution issue unrelated to this change; removing
and re-adding the package dependency (picking `EmojiCatalogCore/` again)
has fixed it before.

## Known limitations

- **No Latin/English typing at all.** Every letter key produces romaji that
  gets converted to hiragana — there's no mode to type plain English. This
  was a deliberate simplification, not an oversight: supporting both would
  need a shift/mode-switch key and case handling, and the priority here was
  Japanese input working well, not feature completeness.
- **No kanji conversion.** This is romaji→hiragana only, not a real
  Japanese IME — かな漢字変換 needs a dictionary-backed conversion engine,
  which is out of scope for this project. The emoji search itself still
  works fine on hiragana input, since `EmojiCatalog.localMatches` already
  matches Japanese keywords by substring.
- **The candidate strip updates on every keystroke**, since there's no
  explicit trigger — closer to the "noisy" built-in IME emoji suggestions
  discussed earlier than the macOS app's on-demand ':' search.
- **Jev requires two separate opt-ins** (a saved API key, and "Allow Full
  Access" in Settings) by design — the keyboard never asks for either on its
  own, and works local-only if neither is set.
- No shift/caps, symbols page, or autocorrect on the key layout itself.
