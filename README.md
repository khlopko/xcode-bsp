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
Right now there is zero automation provided by the tool, you have to configure it manually.

1. Clone the repo in convinient for you way.
2. Build release version:
   ```sh
   swift build -c release
   ```
3. Create link to `/usr/local/bin`:
   ```sh
   ln -s "{PWD}"/.build/release/xcode-bsp /usr/local/bin
   ```
4. In the root folder of the Xcode project create new directory:
   ```sh
   mkdir .bsp
   ```
5. Inside this directory, create new file `xcode-bsp.json` with following contents:
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

   `activeSchemes` is optional. If omitted or empty, `xcode-bsp` will use all schemes from
   `xcodebuild -list`.

Rest is up to [SourceKit's LSP](https://github.com/swiftlang/sourcekit-lsp/blob/ef1178867e7df7d3033d6ec764592fb71846cb67/Contributor%20Documentation/BSP%20Extensions.md).

## alternatives

- [SolaWing/xcode-build-server](https://github.com/SolaWing/xcode-build-server)
