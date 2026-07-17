# Native Anki iOS — Roadmap

Personal project: rebuild an AnkiMobile-style app in SwiftUI, reusing Anki's
Rust backend (`rslib/`) as-is. **No business logic gets rewritten**: the FSRS
scheduler, SQLite storage, AnkiWeb sync, media sync, search — all of it already
lives in the `anki` crate. We cross-compile it for iOS and put a thin UI on
top. No App Store release planned (personal use, so the AGPL license is not a
blocker).

## Working rules (follow these every session)

1. Read this entire file before writing any code. The architecture is
   **decided**: do not re-debate it, do not propose alternatives.
2. Work in order, one step at a time. A step = a state that compiles and
   passes its verification command. Never stack unverified code on top of
   unverified code.
3. After each validated step: tick the checkbox here, then `git commit`
   inside `ios/` (repo initialized in Step 0 — the parent anki-main folder
   is NOT a git repo, never run git at its root).
4. On a build error: read the full message, fix the root cause, re-run the
   same command. Never work around an error by disabling the feature
   involved.
5. The main repo's code (`rslib/`, `proto/`, `pylib/`) is never modified,
   except for adding the `rsbridge-ios` crate to the root workspace.
   Everything new lives in `ios/`.
6. Always the simplest solution: no abstraction with a single use, no
   "manager"/"service" layer on top of `Backend`, no codegen where 10
   hand-written lines suffice. The snippets in this file are the starting
   point — adapt them, don't reinvent them.
7. Stop and ask the user only if: a manual action is required (installing
   Xcode, AnkiWeb login, plugging in the iPhone), or a step still fails
   after 3 serious attempts.

## Architecture (decided — do not re-debate)

- **Backend**: the `anki` crate (rslib) compiled as a `staticlib` for
  `aarch64-apple-ios` + `aarch64-apple-ios-sim`, packaged as an XCFramework.
- **Bridge**: a minimal C FFI crate modeled on `pylib/rsbridge/lib.rs`
  (PyO3 → C ABI, same logic: the backend is opaque, everything travels as
  protobuf bytes).
- **Protocol**: protobuf, the same `.proto` files as the rest of the project
  (`proto/`). Swift side: swift-protobuf for the messages, a hand-written
  `Backend` wrapper. **Do not generate the 200+ RPCs** — only the ones
  listed below.
- **Service/method indices**: assigned by Anki's codegen. Source of truth
  after a build: `out/pylib/anki/_backend_generated.py` (each method there
  calls `self._run_command(service_index, method_index, ...)`) or
  `rslib/rust_interface.rs`. Look up the indices for the RPCs we use and
  hardcode them in a Swift enum, with a comment pointing at the source.
  If `out/` doesn't exist yet, run `just build` first (slow the first
  time — that's normal).
- **UI**: pure SwiftUI, targeting **iOS 26** (Xcode 26 SDK) to get Liquid
  Glass natively. Card rendering happens in a **WKWebView** (cards are
  arbitrary HTML/CSS/JS — never render them natively). Media served via a
  `WKURLSchemeHandler`.
- **Layout**:
  - `ios/rsbridge-ios/` — Rust bridge crate
  - `ios/AnkiApp/` — Xcode project
  - `ios/build-xcframework.sh` — framework packaging
  - `ios/gen-proto.sh` — Swift protobuf message generation

## RPCs needed for v1 (nothing else)

`open_collection`, `close_collection`, `deck_tree`, `get_queued_cards`,
`answer_card`, `describe_next_states` (labels for the 4 answer buttons),
`render_existing_card` (if `get_queued_cards` doesn't provide rendered HTML —
check the proto), `extract_av_tags` (`[sound:...]` audio tags),
`sync_login`, `sync_collection`, `sync_media`, `sync_status`.

## Step 0 — Tooling

- [x] Xcode 26 installed (not just the Command Line Tools) and
      `sudo xcode-select -s /Applications/Xcode.app`
      (as of 2026-07-17: only the CLT are installed → **the user must
      install Xcode first, Claude cannot do it**)
- [x] `rustup` installed, then
      `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
- [x] `git init` inside `ios/` + first commit (this file)
- [x] Verify: `xcodebuild -version` (must show Xcode 26.x) and
      `rustup target list --installed` (must list both iOS targets)

## Step 1 — Cross-compile rslib (risk #1, do this before any Swift)

- [x] From the anki-main root:
      `cargo build --target aarch64-apple-ios -p anki`
      (needs `--features native-tls`, see note below)
- [x] Same with `--target aarch64-apple-ios-sim`
- [x] If it breaks: read the error. Usual suspects: a native build dep
      (protoc — install via brew if asked for), a TLS crate. Fix via Cargo
      features or tool installs. Do not disable sync.
      Hit 3 real issues, all environment/tooling, none required touching
      rslib/proto/pylib:
      1. `protoc` not on PATH for non-interactive shells → pass
         `PROTOC=/opt/homebrew/bin/protoc` explicitly (brew installs it
         unlinked into a non-login-shell PATH).
      2. `ftl/core-repo` and `ftl/qt-repo` are git submodules
         (`anki-core-i18n`, `anki-desktop-ftl`) and anki-main isn't a git
         repo here, so they were never checked out. Cloned them directly
         (shallow) into place instead of `git submodule update` — same
         result, no git needed at anki-main root.
      3. `-p anki` alone doesn't compile: `rslib/Cargo.toml`'s `reqwest`
         with `native-tls` is a **dev-dependency** only; the real build
         gets its TLS backend via the `anki` crate's own `native-tls`/
         `rustls` feature flags, forwarded from `pylib/rsbridge`'s
         features (see `build/configure/src/rust.rs` — non-Linux picks
         `native-tls`). Without a TLS feature, reqwest has no `__tls`
         feature, so `tokio/io-util` never activates and
         `AsyncReadExt`/`AsyncWriteExt`/etc. are missing → build with
         `--features native-tls` (matches the desktop macOS build; the
         future `rsbridge-ios` crate in Step 2 should forward this same
         feature to `anki`).
- [x] Verify: both builds finish with `Finished` and no errors.

## Step 2 — FFI bridge

- [x] Create `ios/rsbridge-ios/` (`crate-type = ["staticlib"]`,
      `anki = { path = "../../rslib" }`), add it to the root
      `Cargo.toml` workspace `members`.
      Also gives it `native-tls`/`rustls` features forwarding to
      `anki/native-tls` / `anki/rustls` (same pattern as
      `pylib/rsbridge`), `native-tls` on by default — see the Step 1 note
      on why a TLS feature is required for `anki` to compile at all.
- [x] `lib.rs` along these lines (adapt by reading `pylib/rsbridge/lib.rs`
      for the exact error handling — backend errors already come back as
      protobuf bytes):

```rust
use anki::backend::{init_backend, Backend};

#[repr(C)]
pub struct ByteBuf { ptr: *mut u8, len: usize }

fn to_buf(v: Vec<u8>) -> ByteBuf { /* leak the Vec, return ptr+len */ }

#[no_mangle]
pub extern "C" fn anki_open_backend(init: *const u8, len: usize) -> *mut Backend {
    // slice from (init, len), init_backend(...), Box::into_raw
    // null on error
}

#[no_mangle]
pub extern "C" fn anki_run_command(
    backend: *mut Backend, service: u32, method: u32,
    input: *const u8, input_len: usize,
    output: *mut ByteBuf, // filled with the response OR the protobuf error
) -> i32 { // 0 = ok, 1 = backend error (output = encoded BackendError)
    // backend.run_service_method(service, method, in_bytes)
}

#[no_mangle]
pub extern "C" fn anki_free_bytes(buf: ByteBuf) { /* rebuild the Vec and drop */ }

#[no_mangle]
pub extern "C" fn anki_close_backend(backend: *mut Backend) { /* Box::from_raw and drop */ }
```

- [x] Hand-written C header `rsbridge.h` (4 functions + the struct).
      Lives in `ios/rsbridge-ios/include/` alongside a `module.modulemap`
      so it can be imported as a Swift module in Step 3.
- [x] `ios/build-xcframework.sh`: `cargo build --release` for both targets,
      then `xcodebuild -create-xcframework -library ... -headers ...`
      → `ios/Anki.xcframework`.
- [x] Verify: the script runs end to end and produces the `.xcframework`.

## Step 3 — Xcode project + Swift layer

- [x] SwiftUI project `ios/AnkiApp`: iOS 26 minimum, iPhone only, links
      `Anki.xcframework` + the header via a module map or bridging header.
      `AnkiApp.xcodeproj/project.pbxproj` was hand-authored (via a
      throwaway generation script, not checked in) rather than created
      through Xcode's GUI — no GUI access in this environment. Classic
      `PBXGroup`/`PBXFileReference` object graph (objectVersion 56), not
      the newer Xcode 16 file-system-synchronized groups, for maximum
      compatibility. `CODE_SIGN_IDENTITY = "-"` (ad-hoc/"Sign to Run
      Locally") since there's no Apple dev team configured yet — fine for
      Simulator, but Step 4's physical-device milestone will need a team
      picked in Xcode (manual, needs the user's Apple ID).
      The xcframework's headers/module map are auto-exposed by Xcode when
      linked (confirmed empirically — an extra explicit
      `HEADER_SEARCH_PATHS` caused a "redefinition of module 'Anki'"
      error and had to be removed).
- [x] swift-protobuf via SPM. `ios/gen-proto.sh`: protoc + the swift plugin
      on the `proto/anki/` files actually used (not the whole folder if
      that avoids import headaches) → `ios/AnkiApp/Generated/`.
      Went with the whole `proto/anki/` folder (25 files): the protos
      cross-import each other heavily and protoc/protoc-gen-swift are
      fast, so curating an exact v1 subset wasn't worth the effort.
      `protoc-gen-swift` installed via `brew install swift-protobuf`.
- [x] `Backend.swift` — an `actor` (FFI calls are blocking, never make them
      on the main thread):
      - `init()`: creates `Application Support/anki/` (collection + media),
        builds the protobuf init message and calls `anki_open_backend`.
        Look at how `pylib/anki/_backend.py` builds this message (preferred
        language, etc.) and reproduce the minimum.
        `init` is `async` (not just `throws`) so it runs on the actor's
        executor and can call other actor-isolated methods (like opening
        the collection) synchronously — a plain sync `init` is treated as
        nonisolated by Swift 6's concurrency checker.
      - `run(_ service: Service, _ method: UInt32, _ input: Data) throws -> Data`
        — if the return code is 1, decode `BackendError` and throw it as a
        typed Swift error.
      - A `Service` enum / method constants with the indices looked up in
        `out/pylib/anki/_backend_generated.py`.
      - The ~12 v1 RPCs as typed methods on top
        (`func deckTree() async throws -> DeckTreeNode`, etc.).
      Two Rust-side FFI hardening fixes needed along the way (in
      `rsbridge-ios/src/lib.rs`): proto3 messages with only default
      values serialize to 0 bytes, and Swift's `Data.withUnsafeBytes` on
      empty `Data` can hand back a null pointer — `slice::from_raw_parts`
      disallows that even for a 0-length slice, so `anki_open_backend`/
      `anki_run_command` now go through a `slice_or_empty` helper.
- [x] Verify (milestone 2): simulator app opens an empty collection and
      prints the decoded `deck_tree` to the console. No UI yet.
      Confirmed on iPhone 17 Pro Simulator (iOS 26.4):
      `deck_tree: AnkiApp.Anki_Decks_DeckTreeNode: children { deck_id: 1
      name: "Default" level: 1 collapsed: true }`. Needed
      `xcrun simctl launch --console` (not `log show`, which doesn't
      capture plain `print()`/stdout) plus an explicit
      `setvbuf(stdout, nil, _IONBF, 0)` in `ContentView.swift`, since
      stdout is fully-buffered off a TTY and a `simctl terminate` (SIGTERM)
      doesn't flush it.

## Step 4 — v1 UI

Goal: it should feel like a real iOS 26 app, not a port. Polish rules that
apply to every screen:

- Standard components first (`NavigationStack`, `List`, `.toolbar`,
  `.searchable` later): they get Liquid Glass automatically with the iOS 26
  SDK. Never rebuild custom chrome where a standard toolbar works.
- Custom chrome (the reviewer's answer bar): `glassEffect(_:in:)` over
  content, buttons grouped in a `GlassEffectContainer`.
- SF Symbols everywhere, never bitmap icons.
- Dynamic Type and dark mode working by default (no hardcoded point sizes
  or hex colors — system semantic colors only).
- Haptics: `.sensoryFeedback` on card answer and sync completion.
- Empty and loading states: `ContentUnavailableView` / `ProgressView`,
  never a blank screen.

Screens:

- [x] **Decks**: `List` from `deck_tree` (flattened hierarchy with
      indentation for v1), new/learn/due counters in system blue/orange/
      green, pull-to-refresh = sync, tap → review.
      Pull-to-refresh currently just reloads `deck_tree`; it'll trigger a
      real sync once the Sync screen below lands.
      No per-deck review selection: the v1 RPC list has no "select deck"
      call, so tapping any row opens the same global review queue
      (get_queued_cards has no deck_id param) — matches the frozen v1 RPC
      list, not a shortcut.
- [x] **Review**: full-screen WKWebView (question → tap or button →
      answer), WebView background matched to the theme
      (`isOpaque = false` + CSS), glass answer bar: one "Show answer"
      button, then 4 buttons Again/Hard/Good/Easy with the intervals from
      `describe_next_states` as subtitles. `answer_card`, then next card
      via `get_queued_cards`. Remaining count in the toolbar (as the
      navigation title, e.g. "3 left").
- [x] **Media**: custom `WKURLSchemeHandler` (e.g. `anki-media://`) that
      reads `collection.media/` and serves files with the right MIME type;
      rewrite the card HTML's relative `src` attributes to this scheme.
      Didn't rewrite the HTML string itself — simpler to load the card
      with `baseURL: URL(string: "anki-media:///")`, so WKWebView resolves
      any relative `src="foo.jpg"` into `anki-media:///foo.jpg` on its own.
- [x] **Audio**: `extract_av_tags` on the rendered HTML, play `[sound:...]`
      via `AVAudioPlayer`, replay button in the toolbar.
      TTS tags are skipped (out of scope for v1, not in the frozen RPC/
      feature list — only plain `soundOrVideo` tags play).
      Added `.sensoryFeedback(.success, trigger:)` on card answer per the
      Step 4 polish rules.
      Verification caveat: the local test collection is empty (0 cards),
      so Decks/Review's happy paths with real content, and Media/Audio
      specifically, could only be verified by (a) confirming the app
      builds clean and (b) confirming the correct empty-state UI renders
      end-to-end (`ContentUnavailableView` "All Done" from a real
      `get_queued_cards` call returning zero cards) — screenshotted on
      iPhone 17 Pro Simulator. Rendering a card with real
      images/audio/`[sound:...]` tags needs actual due cards, which only
      exist once milestone 4 (AnkiWeb sync) has pulled real data — so
      that part of the verification is folded into milestone 3 below,
      same as the roadmap already specifies.
- [ ] **Sync**: AnkiWeb login sheet (`sync_login`, hkey stored in the
      **Keychain**, never UserDefaults), auto-sync on launch when
      credentials exist, discreet indicator in the decks toolbar, errors
      as `.alert`.
- [ ] Verify (milestone 3): review a real card (with image and audio) on a
      physical iPhone.
- [ ] Verify (milestone 4): round-trip sync with AnkiWeb **on a test
      account or a copy of the account** — never the real account until
      this is validated. Check on desktop that nothing got corrupted.

## Step 5 — Later, only once milestone 4 is green

Undo, mark/suspend/bury from the reviewer, card editor, browser/search,
stats, FSRS settings, widgets/App Intents. None of this before then. If the
user explicitly asks for one of these, first add it here as a new checkable
step.
