# Emojichao Keyboard (iOS)

An add-on keyboard (switch to it with the globe key, same as Gboard/Simeji)
that searches emoji by the word you're currently typing — no explicit
trigger needed. The keys copy the iPhone's own **日本語かな** keyboard (12-key
flick layout with トグル input, 小゛゜, and ABC/☆123 modes), without kanji
conversion — see "Known limitations" below. It reuses the
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
  subclass: draws the iPhone 日本語かな key layout (☆123/ABC/あいう on the
  left, the あかさ… grid, ⌫/空白/改行 on the right), holds kana as marked
  text until 確定, tracks the word being typed since the last
  boundary (space/return/punctuation), and shows matches in a candidate
  strip above the keys, updated on every keystroke. Tapping a candidate
  deletes the typed word and inserts the emoji in its place. Extension-only
  (add to the keyboard extension target).
- `EmojichaoKeyboard/EmojiCandidateStripView.swift` — the horizontally
  scrolling row of tappable emoji candidates, drawn by the extension itself
  (neither iOS nor Android give third-party keyboards a way to inject into
  the system's own predictive-text bar). Extension-only.
- `EmojichaoKeyboard/FlickKeyLayout.swift` — the key tables for the kana,
  alphabet and number modes (flick directions, トグル cycles, 小゛゜ / a/A
  transforms). Extension-only.
- `EmojichaoKeyboard/KanaKanjiEngine.swift` — the composing reading and
  its kanji conversions (wraps AzooKeyKanaKanjiConverter; the keyboard
  target links its `KanaKanjiConverterModuleWithDefaultDictionary`
  product). Extension-only.
- `EmojichaoKeyboard/FlickKeyButton.swift` — the flick key itself: tells a
  tap from a flick in four directions. Extension-only.
- `EmojichaoShared/JevKeyStore.swift` — reads/writes the Jev API key in an
  App Group–shared `UserDefaults`, so the container app (where it's typed
  in) and the extension (where it's used) can both reach it. **Add this one
  file to BOTH targets.**
- `EmojichaoShared/KeyboardSettings.swift` — keyboard options set in the
  app (currently フリックのみ), read by the extension through the same App
  Group. **Add this one to BOTH targets too.**
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

- **Kanji conversion is on-device** via
  [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)
  (MIT) and its default dictionary (Apache-2.0), pinned to 0.11.x. Its
  swift-collections dependency is capped below 1.3: newer releases call a
  Swift runtime function (`swift_initBorrow`) that iOS 18/26 don't have,
  and the keyboard fails to load. The dictionary adds about 38 MB.
  Conversion quality is plain dictionary-based (no Zenzai); learning from
  picks is on and stored in the App Group. Conversion runs on a
  background queue, so keys never wait on it. The package is about 6×
  slower unoptimized (~80 ms vs ~13 ms per key in the simulator), so both
  schemes' Run action uses the Release configuration. Emoji are matched on both the
  converted text (猫) and the reading (ねこ); Jev gets the converted text
  plus up to 200 characters before the cursor as context.
- **Only kana compose.** ABC/☆123 input goes straight into the document,
  with no English prediction. If the host app commits the marked text on
  its own (e.g. the user taps elsewhere mid-composition), the keyboard
  doesn't notice and the next keystroke may re-mark the old reading.
- **The candidate strip updates on every keystroke**, since there's no
  explicit trigger — closer to the "noisy" built-in IME emoji suggestions
  discussed earlier than the macOS app's on-demand ':' search.
- **Jev requires two separate opt-ins** (a saved API key, and "Allow Full
  Access" in Settings) by design — the keyboard never asks for either on its
  own, and works local-only if neither is set.
- No autocorrect, kaomoji (^^) key, or flick guide ring — the flick preview
  is a single bubble beside the key.
- The 空白 / emoji-globe slots are drawn as blank, inert keys; the
  system's own globe below the keyboard switches keyboards.
- 左寄せ / 通常 / 右寄せ is picked from buttons in the candidate strip while
  no word is being typed, since third-party keyboards can't add items to
  the system globe key's long-press menu.
