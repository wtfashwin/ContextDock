# Build Report — v0.1 (2026-07-30)

Environment: macOS 26.5.2 (Apple Silicon), Command Line Tools only
(no Xcode.app), Apple Swift 6.3.3, deployment target macOS 15.

| Step | Command | Result |
|---|---|---|
| Debug build | `swift build` | ✅ Build complete |
| Tests | `./scripts/test.sh` | ✅ 36/36 passed |
| Release build + bundle | `./scripts/make_app.sh` | ✅ `build/ContextDock.app` (ad-hoc signed) |
| Launch | `open build/ContextDock.app` | ✅ resident accessory app, island visible, socket + store created |
| Live socket probe | external client → `events.sock` | ✅ event ingested and persisted |

Build fixes applied during bring-up:

1. `SecretRedactor.patterns` — `Regex` is not `Sendable`; marked
   `nonisolated(unsafe)` (immutable after init).
2. Swift Testing macro expansion cannot call `mutating` members inside
   `#expect` — hoisted calls to lets.
3. Testing.framework / `lib_TestingInterop.dylib` live outside default CLT
   search paths — `scripts/test.sh` adds `-F`/`-rpath` flags.
4. Socket queue deadlock (see TEST_REPORT.md).
