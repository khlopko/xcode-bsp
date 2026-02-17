> [!Important]
> State-of-the-art implementation, may contain issues or don't work on particular projects.

![hero](hero.png)

# xcode-bsp
Xcode Build Server Protocol implementation in Swift. 

Aims to provide support for Xcode projects in other editors that rely on [sourcekit-lsp](https://github.com/swiftlang/sourcekit-lsp). 

## current state
Capable to run completion requests. Missing diagnostics. Really slow on start.

Implemented methods:
- `build/initialize`
- `build/shutdown`
- `build/exit`
- `textDocument/registerForChanges`
- `workspace/buildTargets`
- `buildTarget/sources`
- `buildTarget/prepare` (currently disabled)
- `textDocument/sourceKitOptions`

## how to: install
There is now a setup script and an interactive config command.

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
  "version": "0.1.0",
  "bspVersion": "2.0.0",
  "languages": ["swift", "objective-c", "objective-cpp", "c", "cpp"],
  "activeSchemes": []
}
```

Rest is up to [SourceKit's LSP](https://github.com/swiftlang/sourcekit-lsp/blob/ef1178867e7df7d3033d6ec764592fb71846cb67/Contributor%20Documentation/BSP%20Extensions.md).

## alternatives

- [SolaWing/xcode-build-server](https://github.com/SolaWing/xcode-build-server)
