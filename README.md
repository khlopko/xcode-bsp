> [!Caution]
> Under development, may contain issues and _do_ contain missing functionality.

# xcode-bsp
Xcode Build Server Protocol implementation, in Swift.

## current state
Supports completion from default frameworks, but fails to get project contents.
Handles following methods currently:

- `build/initialize`
- `build/shutdown`
- `build/exit`
- `textDocument/registerForChanges`
- `workspace/buildTargets`
- `buildTarget/sources`

Missing:

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
     "languages": ["swift", "objective-c", "objective-cpp", "c", "cpp"]
   }
   ```

Rest is up to SourceKit's LSP.
