> [!WARNING]
> Alpha software (v0.2.x). Ready for early adopters, but not yet stable.

![hero](hero.png)

# xcode-bsp
Xcode Build Server Protocol implementation in Swift.

Aims to provide support for Xcode projects in editors that rely on [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp).

## status
- Stage: **Alpha / Early Access** (`0.2.x`).
- Readiness: usable for early adopters and daily experimentation.
- Not yet implemented: diagnostics support.
- Expected behavior: first requests can be slower while caches are populated.
- Platform requirement: `macOS 14+` (`Package.swift`).

## implemented protocol surface
Incoming requests:
- `build/initialize`
- `build/shutdown`
- `workspace/buildTargets`
- `workspace/waitForBuildSystemUpdates`
- `textDocument/registerForChanges`
- `buildTarget/sources`
- `buildTarget/inverseSources`
- `buildTarget/prepare` (best-effort cache warmup)
- `textDocument/sourceKitOptions`

Incoming notifications:
- `build/initialized`
- `workspace/didChangeWatchedFiles`
- `build/exit`

Outgoing notifications:
- `buildTarget/didChange`
- `build/sourceKitOptionsChanged`

## install
Use the setup script and interactive config command.

1. Clone the repo.
2. Run setup:
   ```sh
   ./build_release.sh
   ```
   This builds the release binary and installs a symlink to `/usr/local/bin/xcode-bsp`.
3. In the root folder of your Xcode project, generate BSP config:
   ```sh
   xcode-bsp config
   ```
   The command asks which schemes to include as active build targets and writes `.bsp/xcode-bsp.json`.

`activeSchemes` is optional in config. If omitted or empty, `xcode-bsp` uses all schemes from
`xcodebuild -list`.

Manual config is still supported. Example `.bsp/xcode-bsp.json`:
```json
{
  "name": "xcode-bsp",
  "argv": ["/usr/local/bin/xcode-bsp"],
  "version": "0.2.0",
  "bspVersion": "2.0.0",
  "languages": ["swift", "objective-c", "objective-cpp"],
  "activeSchemes": []
}
```

## known limitations
- Diagnostics are not implemented yet.
- Project-specific edge cases still exist.
- Cache warmup can make first-response latency noticeably higher.

## development
- Build: `swift build`
- Test: `swift test`

Rest is up to [SourceKit's LSP](https://github.com/swiftlang/sourcekit-lsp/blob/ef1178867e7df7d3033d6ec764592fb71846cb67/Contributor%20Documentation/BSP%20Extensions.md).

## alternatives

- [SolaWing/xcode-build-server](https://github.com/SolaWing/xcode-build-server)
