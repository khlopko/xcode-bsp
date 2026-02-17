# Agent Guide for xcode-bsp

This document is for coding agents working in this repository. It captures how to build, test, and follow existing coding style.

Last verified: 2026-02-18

## Repository Overview
- Swift Package Manager (SPM) executable target: `XcodeBSP`
- Main entry point: `Sources/XcodeBSP/App.swift`
- Protocol handlers under: `Sources/XcodeBSP/BuildServerProtocol/Handlers`

## Implementation Snapshot
- Transport is stdio JSON-RPC in `JSONRPCConnection` (reads `Content-Length` frames and writes encoded responses).
- Request/notification dispatch happens in `XcodeBuildServer` through `HandlersRegistry`.
- Xcode integration is centralized in `Xcode/XcodeBuild.swift` using `xcodebuild -json` (`-list`, `-showBuildSettings`, `-showBuildSettingsForIndex`).
- Compiler arguments are cached in two layers:
  - In-memory + file caches for raw `xcodebuild` JSON.
  - SQLite cache (`Cache/Database.swift`) for normalized per-file compiler arguments.
- Target IDs are URI-based (`xcode://<project>?scheme=<scheme>[&target=<target>]`).

## Build, Run, Lint, Test

### Build
- Debug build (default):
  - `swift build`
- Release build:
  - `swift build -c release`
- One-step setup/install on macOS:
  - `./build_release.sh`
  - Builds release binary, links `/usr/local/bin/xcode-bsp`, and copies a config template to clipboard.
- Clean build artifacts:
  - `swift package clean`

### Run
- Run the executable via SPM:
  - `swift run xcode-bsp`
- Run with an explicit action (see `App.swift`):
  - `swift run xcode-bsp config`
  - `swift run xcode-bsp server`
- Run installed binary (recommended for project setup):
  - `xcode-bsp config` (run in Xcode project root; interactively selects schemes and writes `.bsp/xcode-bsp.json`)
  - `xcode-bsp server`

### Test
- Run all tests (if/when tests exist):
  - `swift test`
- Run a single test (SPM filter):
  - `swift test --filter <ModuleTests>/<testName>`
  - Example: `swift test --filter XcodeBSPTests/testBuildInitialize`

### Lint / Format
- No lint or formatter configuration found (no SwiftLint/SwiftFormat config).
- If you add a formatter, document the command here and align with existing style.

## Cursor / Copilot Rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.
- If you add any, update this document with their key requirements.

## Code Style and Conventions

### Formatting
- Indentation: 4 spaces.
- Braces on the same line as declarations (K&R style).
- Prefer trailing commas in multiline argument/array/dictionary literals.
- Use blank lines to separate logical blocks (setup, compute, action).
- Keep line width reasonable; wrap long argument lists over multiple lines.

### Imports
- Use one import per line.
- Prefer Foundation first, then external modules, then local modules.
- Avoid unused imports.

### Types and Structures
- Use `struct` for value types and small containers.
- Use `final class` for reference types (see `XcodeBuildServer`, `JSONRPCConnection`).
- Use `actor` for shared mutable state (`Database`).
- Conform to `Sendable` where concurrency crosses threads or tasks.
- Prefer nested types for request/response payloads and error enums.

### Naming
- Types: UpperCamelCase.
- Methods/vars: lowerCamelCase.
- Protocols: descriptive nouns (`MethodHandler`).
- Avoid abbreviations unless well known (e.g., `URL`, `JSON`).
- Use explicit names for errors: `InitializationError`, `UnhandledMethodError`.

### Error Handling
- Favor `throws` + `do/catch` over `fatalError`.
- Define small, local error enums/structs for context.
- Use `guard` for early exits and input validation.
- Log errors with `Logger` when they should be observable, but avoid noisy logs.

### Logging
- Use `makeLogger(label:)` to create a logger.
- Logging uses a JSON file handler at `/tmp/xcode-bsp/default.log`.
- Prefer `.debug` for normal flow and `.error` for failures.

### Concurrency
- Use `async/await` for handler processing.
- When bridging from synchronous contexts, launch a `Task`.
- Keep `Sendable` boundaries clear; avoid sharing non-thread-safe state.

### JSON / Encoding
- Prefer `JSONDecoder` and `JSONEncoder` with explicit use in each component.
- Keep payload types `Decodable`/`Encodable` and nested under their handlers.
- In responses, wrap results in the `Response` type.

### Build Server Protocol Handlers
- Each handler implements `MethodHandler`.
- `method` should match the BSP method string exactly.
- Keep handler logic focused; use helper types/services for heavy work.
- Return `Response<Result>` via the `MethodHandler.handle` default implementation.
- Notifications should conform to `NotificationMethodHandler`.
- Current notification coverage includes `build/initialized`, `workspace/didChangeWatchedFiles`, and `build/exit`.

### File and Path Handling
- Use `FileManager` and `URL` helpers.
- Prefer `URL(filePath:)` and `.appending(component:)` for composition.
- Use `.path()` only when you must pass a string path to APIs.

### Database Access
- The `Database` actor owns the SQLite connection.
- Use actor isolation; avoid external connection reuse.
- Use transactions for multi-row writes.
- Throw a specific `NotFoundError` when expected data is missing.

## Practical Guidance

### Adding a New BSP Handler
1. Create a new type in `Sources/XcodeBSP/BuildServerProtocol/Handlers`.
2. Conform it to `MethodHandler` with nested `Params`/`Result` types.
3. Register it in `XcodeBuildServer`’s `HandlersRegistry`.
4. Keep JSON parsing in the handler; push heavy logic into a helper.

### Updating Config Generation
- Config creation lives in `Sources/XcodeBSP/App.swift`.
- Keep generated JSON in `Config` and use `JSONEncoder`.
- Only update `.bsp/xcode-bsp.json` via `Config.configURL()`.
- `xcode-bsp config` is interactive and stores selected schemes in `activeSchemes`.
- If `activeSchemes` is missing or empty, all schemes from `xcodebuild -list` are used.
- `workspace/buildTargets` and `build/initialize` both rely on config load succeeding.

### Compiler Arguments Flow
- Primary method is `textDocument/sourceKitOptions`.
- Parse scheme/target from `TargetID.uri`, parse file path from `textDocument.uri`.
- Read per-file args from `Database`; if missing, compute via `XcodeBuild.settingsForIndex`.
- Sanitize unsupported/unstable args (`-use-frontend-parseable-output`, localized strings flags).
- Detect missing SDK paths and refresh arguments with cache bypass before responding.
- Persist refreshed args back to SQLite, scoped by scheme or `scheme::target`.

### Caching Notes
- Workspace-specific cache filenames are derived from workspace name + SHA256 digest.
- `XcodeBuild` keeps memory caches and backs them with files in `~/Library/Caches/xcode-bsp`.
- Database schema deduplicates argument payloads via `argument_sets(hash, payload)` and maps files via `file_arguments`.
- Logs are JSON lines in `/tmp/xcode-bsp/default.log`.

### Common Commands Recap
- Build debug: `swift build`
- Build release: `swift build -c release`
- Setup/install: `./build_release.sh`
- Run: `swift run xcode-bsp`
- Configure active schemes (project root): `xcode-bsp config`
- Test all: `swift test`
- Test single: `swift test --filter <ModuleTests>/<testName>`

## Files to Know
- `Package.swift`: SwiftPM manifest and dependencies.
- `Sources/XcodeBSP/App.swift`: CLI entry point.
- `Sources/XcodeBSP/XcodeBuildServer.swift`: main server loop.
- `Sources/XcodeBSP/JSONRPCConnection.swift`: stdio JSON-RPC transport.
- `Sources/XcodeBSP/Xcode/XcodeBuild.swift`: `xcodebuild` adapter and caches.
- `Sources/XcodeBSP/BuildServerProtocol/Handlers`: BSP method handlers.
- `Sources/XcodeBSP/Logger.swift`: logging implementation.
- `Sources/XcodeBSP/Cache/Database.swift`: SQLite cache storage.

## Notes for Agents
- Avoid introducing new build steps or tooling unless requested.
- Keep changes consistent with existing style and structure.
- If you add tests or linters, document the commands in this file.
