> [!WARNING]
> Alpha software (v0.3.0). It might not be stable yet.

![hero](hero.png)

# xcode-bsp
Xcode Build Server Protocol implementation in Swift.

[![Build](https://github.com/khlopko/xcode-bsp/actions/workflows/ci.yml/badge.svg)](https://github.com/khlopko/xcode-bsp/actions/workflows/ci.yml)

Aims to provide support for Xcode projects in editors that rely on [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp).

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
Use the setup script, then generate project config with `xcode-bsp config`.

1. Clone the repo.
2. Run setup:
   ```sh
   ./build_release.sh
   ```
   This builds the release binary and installs a symlink to `/usr/local/bin/xcode-bsp`.
3. In the root folder of your Xcode project, run:
   ```sh
   xcode-bsp config
   ```
   The command:
   - asks which schemes to include as active build targets,
   - asks for executable path (defaults to detected current `xcode-bsp` path),
   - writes `.bsp/xcode-bsp.json`.

If you want to skip the executable-path prompt and set it explicitly:
```sh
xcode-bsp config --executable-path /absolute/path/to/xcode-bsp
```

`activeSchemes` is optional in config. If omitted or empty, `xcode-bsp` uses all schemes from
`xcodebuild -list`.

Manual config is still supported. Example `.bsp/xcode-bsp.json`:
```json
{
  "name": "xcode-bsp",
  "argv": ["/absolute/path/to/xcode-bsp"],
  "version": "0.3.0",
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
