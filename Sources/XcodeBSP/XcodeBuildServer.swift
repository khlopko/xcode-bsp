import CryptoKit
import Foundation
import Logging

final class XcodeBuildServer {
    private let queue: DispatchQueue
    private let source: DispatchSourceRead
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: Logger

    init() throws {
        queue = DispatchQueue(label: "local.sourcekit.bsp")
        source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        logger = try makeLogger(label: "xcode-bsp")
    }
}

extension XcodeBuildServer {
    func run() throws {
        source.setEventHandler { [weak self] in
            self?.receiveMessage()
        }
        source.resume()

        RunLoop.current.run()
    }

    private func receiveMessage() {
        do {
            let data = FileHandle.standardInput.availableData
            guard data.isEmpty == false, let sep = "\r\n\r\n".data(using: .utf8) else {
                return
            }

            let parts = data.split(separator: sep)
            guard parts.count == 2 else {
                logger.error("expected 2 parts of message, got \(parts.count)")
                return
            }

            let baseReq = try decoder.decode(BaseRequest.self, from: parts[1])
            try dispatch(baseReq: baseReq, contents: parts[1])
        } catch {
            logger.error("\(error)")
        }
    }
}

extension XcodeBuildServer {
    struct BaseRequest: Decodable {
        let method: String
    }
}

extension XcodeBuildServer {
    struct Request<Params>: Decodable, CustomStringConvertible where Params: Decodable {
        var description: String {
            return "{\"id\":\"\(id)\",\"method\":\"\(method)\",\"params\":\"\(params)\"}"
        }

        struct InvalidJSONError: Error {
            let data: Data
        }

        struct InvlidFieldError: Error {
            let key: String
            let value: any Sendable
            let expectedType: Any.Type
        }

        let id: String
        let method: String
        let params: Params
    }
}

extension XcodeBuildServer {
    private var routes: [String: (Data) throws -> Void] {
        [
            "build/initialize": buildInitialize(data:),
            "build/shutdown": buildShutdown(data:),
            "build/exit": buildExit(data:),
            "textDocument/registerForChanges": textDocumentRegisterForChanges(data:),
            "workspace/buildTargets": workspaceBuildTargets(data:),
            "buildTarget/sources": buildTargetSources(data:),
            //"textDocument/sourceKitOptions": textDocumentSourceKitOptions(data:),
        ]
    }

    struct UnhandledMethodError: Error {
        let method: String
        let data: Data
    }

    func dispatch(baseReq: BaseRequest, contents: Data) throws {
        guard let route = routes[baseReq.method] else {
            logger.error("unhandled method: \(baseReq.method)")
            logger.debug("unhandled message: \(String(data: contents, encoding: .utf8) ?? "")")
            return
        }

        try route(contents)
    }

    struct InitializeParams: Decodable {
    }

    struct Response<Result>: Encodable where Result: Encodable {
        let jsonrpc: String = "2.0"
        let id: String
        let result: Result
    }

    struct EmptyResult: Encodable {
    }

    struct InitializeResult: Encodable {
        let displayName: String = "xcode-bsp"
        let version: String = "0.1.0"
        let bspVersion: String = "2.0.0"
        let capabilities: Capabilities
        let dataKind: String = "sourceKit"
        let data: SourceKitData?

        struct Capabilities: Encodable {
            let languageIds: [String] = ["swift", "objective-c", "objective-cpp", "c", "cpp"]
        }

        struct SourceKitData: Encodable {
            let indexDatabasePath: String
            let indexStorePath: String
            let sourceKitOptionsProvider: Bool = true
        }
    }

    struct XcodeBuildSettings: Decodable {
        let target: String
        let action: String
        let buildSettings: BuildSettings

        struct BuildSettings: Decodable {
            let BUILD_DIR: String
            let BUILD_ROOT: String
            let PROJECT: String
            let SOURCE_ROOT: String
        }
    }

    private func buildInitialize(data: Data) throws {
        let req = try decoder.decode(Request<InitializeParams>.self, from: data)
        logger.debug("\(#function): \(req)")

        var sourceKitData: InitializeResult.SourceKitData?
        let output = shell("xcodebuild -showBuildSettings -json")
        if let outputData = output.text?.data(using: .utf8) {
            let xcodeBuildSettings = try decoder.decode([XcodeBuildSettings].self, from: outputData)
            // just taking first target with action: "build"
            if let buildableTarget = xcodeBuildSettings.first(where: { $0.action == "build" }) {
                logger.debug("xcode build settings: \(buildableTarget)")
                let indexStorePath = buildableTarget.buildSettings.BUILD_ROOT
                let cachePath = "~/Library/Caches/xcode-bsp"
                var sha256 = SHA256()
                sha256.update(data: indexStorePath.data(using: .utf8)!)
                let digest = sha256.finalize().split(separator: Character(":").asciiValue!)[1]
                sourceKitData = InitializeResult.SourceKitData(
                    indexDatabasePath: cachePath + "/indexDatabase-\(digest)",
                    indexStorePath: indexStorePath
                )
            }
        }

        let resp = Response(
            id: req.id,
            result: InitializeResult(
                capabilities: InitializeResult.Capabilities(),
                data: sourceKitData
            )
        )
        try send(resp)
    }

    struct EmptyParams: Decodable {
    }

    struct WorkspaceBuildTargetsResult: Encodable {
        let targets: [Target]

        struct Target: Encodable {
            let id: ID
            let displayName: String
            let tags: [String] = []
            let languageIds: [String] = ["swift", "objective-c", "objective-cpp", "c", "cpp"]
            let dependencies: [ID] = []
            let capabilities: Capabilities = Capabilities()

            struct ID: Encodable {
                let uri: String
            }

            struct Capabilities: Encodable {
            }
        }
    }

    private func workspaceBuildTargets(data: Data) throws {
        let req = try decoder.decode(Request<EmptyParams>.self, from: data)

        var targets: [WorkspaceBuildTargetsResult.Target] = []

        let output = shell("xcodebuild -showBuildSettings -json")
        if let outputData = output.text?.data(using: .utf8) {
            let xcodeBuildSettings = try decoder.decode([XcodeBuildSettings].self, from: outputData)
            // just taking first target with action: "build"
            if let buildableTarget = xcodeBuildSettings.first(where: { $0.action == "build" }) {
                let target = WorkspaceBuildTargetsResult.Target(
                    id: WorkspaceBuildTargetsResult.Target.ID(
                        uri: "\(buildableTarget.buildSettings.PROJECT)://\(buildableTarget.target)"),
                    displayName: buildableTarget.target
                )
                targets.append(target)
            }
        }

        logger.debug("targets: \(targets)")
        let result = WorkspaceBuildTargetsResult(targets: targets)
        let resp = Response(id: req.id, result: result)
        try send(resp)
    }

    struct BuildTargetSourcesParams: Decodable {
        let targets: [TargetID]

        struct TargetID: Decodable {
            let uri: String
        }
    }

    struct BuildTargetSourcesResult: Encodable {
        let items: [SourcesItem]

        struct SourcesItem: Encodable {
            let target: TargetID
            let sources: [SourceItem]

            struct TargetID: Encodable {
                let uri: String
            }

            struct SourceItem: Encodable {
                let uri: String
                let kind: Kind
                let generated: Bool

                enum Kind: Int, Encodable {
                    case file = 1
                    case dir = 2
                }
            }
        }
    }

    private func buildTargetSources(data: Data) throws {
        let req = try decoder.decode(Request<BuildTargetSourcesParams>.self, from: data)

        var items: [BuildTargetSourcesResult.SourcesItem] = []
        for target in req.params.targets {
            guard let scheme = target.uri.split(separator: "://").last else {
                logger.error("invalid target id: \(target)")
                continue
            }

            let output = shell("xcodebuild -showBuildSettings -json")
            guard let outputData = output.text?.data(using: .utf8) else {
                logger.error("no scheme for target: \(target)")
                continue
            }

            do {
                let xcodeBuildSettings = try decoder.decode(
                    [XcodeBuildSettings].self, from: outputData)
                guard let xcodeTarget = xcodeBuildSettings.first(where: { $0.target == scheme })
                else {
                    logger.error("no settings for scheme: \(scheme)")
                    continue
                }

                let item = BuildTargetSourcesResult.SourcesItem(
                    target: BuildTargetSourcesResult.SourcesItem.TargetID(uri: target.uri),
                    sources: [
                        BuildTargetSourcesResult.SourcesItem.SourceItem(
                            uri: "file://" + xcodeTarget.buildSettings.SOURCE_ROOT + "/",
                            kind: .dir,
                            generated: false
                        )
                    ]
                )
                items.append(item)
            } catch {
                logger.error("settings decoding failed: \(error)")
                continue
            }
        }

        logger.debug("sources: \(items)")
        let result = BuildTargetSourcesResult(items: items)
        let resp = Response(id: req.id, result: result)
        try send(resp)
    }

    struct TextDocumentRegisterForChangesParams: Decodable {
    }

    private func textDocumentRegisterForChanges(data: Data) throws {
        let req = try decoder.decode(Request<TextDocumentRegisterForChangesParams>.self, from: data)
        let resp = Response(id: req.id, result: EmptyResult())
        try send(resp)
    }

    struct TextDocumentSourceKitOptionsParams: Decodable {
        let language: String
        let textDocument: TextDocument
        let target: TargetID

        struct TextDocument: Decodable {
            let uri: String
        }

        struct TargetID: Decodable {
            let uri: String
        }
    }

    struct TextDocumentSourceKitOptionsResult: Encodable {
        let compilerArguments: [String]
        let workingDirectory: String?
    }

    private func textDocumentSourceKitOptions(data: Data) throws {
        let req = try decoder.decode(Request<TextDocumentSourceKitOptionsParams>.self, from: data)

        var result: TextDocumentSourceKitOptionsResult?

        let output = shell("xcodebuild -showBuildSettings -json")
        if let outputData = output.text?.data(using: .utf8) {
            do {
                let xcodeBuildSettings = try decoder.decode(
                    [XcodeBuildSettings].self, from: outputData)
                if let scheme = req.params.target.uri.split(separator: "://").last,
                    let xcodeTarget = xcodeBuildSettings.first(where: { $0.target == scheme })
                {
                    result = TextDocumentSourceKitOptionsResult(
                        compilerArguments: [],
                        workingDirectory: xcodeTarget.buildSettings.BUILD_ROOT
                    )
                }
            } catch {
            }
        }

        let resp = Response(id: req.id, result: result)
        try send(resp)
    }

    struct ShutdownParams: Decodable {
    }

    private func buildShutdown(data: Data) throws {
        source.suspend()
        let req = try decoder.decode(Request<EmptyParams>.self, from: data)
        let resp = Response(id: req.id, result: EmptyResult())
        try send(resp)
    }

    struct ExitParams: Decodable {
    }

    private func buildExit(data: Data) throws {
        exit(0)
    }

    private func send(_ resp: some Encodable) throws {
        let data = try encoder.encode(resp)
        let header = "Content-Length: \(data.count)\r\n\r\n".data(using: .utf8)!
        FileHandle.standardOutput.write(header + data)
    }
}
