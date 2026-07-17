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

- [ ] Create `ios/rsbridge-ios/` (`crate-type = ["staticlib"]`,
      `anki = { path = "../../rslib" }`), add it to the root
      `Cargo.toml` workspace `members`.
- [ ] `lib.rs` along these lines (adapt by reading `pylib/rsbridge/lib.rs`
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

- [ ] Hand-written C header `rsbridge.h` (4 functions + the struct).
- [ ] `ios/build-xcframework.sh`: `cargo build --release` for both targets,
      then `xcodebuild -create-xcframework -library ... -headers ...`
      → `ios/Anki.xcframework`.
- [ ] Verify: the script runs end to end and produces the `.xcframework`.

## Step 3 — Xcode project + Swift layer

- [ ] SwiftUI project `ios/AnkiApp`: iOS 26 minimum, iPhone only, links
      `Anki.xcframework` + the header via a module map or bridging header.
- [ ] swift-protobuf via SPM. `ios/gen-proto.sh`: protoc + the swift plugin
      on the `proto/anki/` files actually used (not the whole folder if
      that avoids import headaches) → `ios/AnkiApp/Generated/`.
- [ ] `Backend.swift` — an `actor` (FFI calls are blocking, never make them
      on the main thread):
      - `init()`: creates `Application Support/anki/` (collection + media),
        builds the protobuf init message and calls `anki_open_backend`.
        Look at how `pylib/anki/_backend.py` builds this message (preferred
        language, etc.) and reproduce the minimum.
      - `run(_ service: Service, _ method: UInt32, _ input: Data) throws -> Data`
        — if the return code is 1, decode `BackendError` and throw it as a
        typed Swift error.
      - A `Service` enum / method constants with the indices looked up in
        `out/pylib/anki/_backend_generated.py`.
      - The ~12 v1 RPCs as typed methods on top
        (`func deckTree() async throws -> DeckTreeNode`, etc.).
- [ ] Verify (milestone 2): simulator app opens an empty collection and
      prints the decoded `deck_tree` to the console. No UI yet.

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

- [ ] **Decks**: `List` from `deck_tree` (flattened hierarchy with
      indentation for v1), new/learn/due counters in system blue/orange/
      green, pull-to-refresh = sync, tap → review.
- [ ] **Review**: full-screen WKWebView (question → tap or button →
      answer), WebView background matched to the theme
      (`isOpaque = false` + CSS), glass answer bar: one "Show answer"
      button, then 4 buttons Again/Hard/Good/Easy with the intervals from
      `describe_next_states` as subtitles. `answer_card`, then next card
      via `get_queued_cards`. Remaining count in the toolbar.
- [ ] **Media**: custom `WKURLSchemeHandler` (e.g. `anki-media://`) that
      reads `collection.media/` and serves files with the right MIME type;
      rewrite the card HTML's relative `src` attributes to this scheme.
- [ ] **Audio**: `extract_av_tags` on the rendered HTML, play `[sound:...]`
      via `AVAudioPlayer`, replay button in the toolbar.
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
