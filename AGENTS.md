# Agent Guide for xcode-bsp

This document is for coding agents working in this repository. It captures how to build, test, and follow existing coding style.

Last verified: 2026-02-17

## Repository Overview
- Swift Package Manager (SPM) executable target: `XcodeBSP`
- Main entry point: `Sources/XcodeBSP/App.swift`
- Protocol handlers under: `Sources/XcodeBSP/BuildServerProtocol/Handlers`

## Build, Run, Lint, Test

### Build
- Debug build (default):
  - `swift build`
- Release build:
  - `swift build -c release`
- Clean build artifacts:
  - `swift package clean`

### Run
- Run the executable via SPM:
  - `swift run xcode-bsp`
- Run with an explicit action (see `App.swift`):
  - `swift run xcode-bsp config`
  - `swift run xcode-bsp server`

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

### Common Commands Recap
- Build debug: `swift build`
- Build release: `swift build -c release`
- Run: `swift run xcode-bsp`
- Test all: `swift test`
- Test single: `swift test --filter <ModuleTests>/<testName>`

## Files to Know
- `Package.swift`: SwiftPM manifest and dependencies.
- `Sources/XcodeBSP/App.swift`: CLI entry point.
- `Sources/XcodeBSP/XcodeBuildServer.swift`: main server loop.
- `Sources/XcodeBSP/BuildServerProtocol/Handlers`: BSP method handlers.
- `Sources/XcodeBSP/Logger.swift`: logging implementation.
- `Sources/XcodeBSP/Cache/Database.swift`: SQLite cache storage.

## Notes for Agents
- Avoid introducing new build steps or tooling unless requested.
- Keep changes consistent with existing style and structure.
- If you add tests or linters, document the commands in this file.
