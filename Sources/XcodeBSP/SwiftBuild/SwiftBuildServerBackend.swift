import BuildServerProtocol
import Foundation
import LanguageServerProtocol
import LanguageServerProtocolTransport
import Logging
import SwiftBuild

import func SWBBuildService.swiftbuildServiceEntryPoint

final class SwiftBuildServerBackend: @unchecked Sendable {
    private let cacheDir: URL
    private let config: Config
    private let logger: Logger

    private let shutdownLock = NSLock()
    private var didShutdown = false

    private var transport: LanguageServerProtocolTransport.JSONRPCConnection?
    private var service: SWBBuildService?
    private var session: SWBBuildServiceSession?

    init(cacheDir: URL, config: Config) throws {
        self.cacheDir = cacheDir
        self.config = config

        var logger = try makeLogger(label: "xcode-bsp.swiftbuild")
        logger.logLevel = .trace
        self.logger = logger
    }

    func run() throws {
        logger.debug("swift-build backend startup begin")
        let startup: StartupRuntime
        do {
            startup = try waitForAsync { [self] in
                try await createRuntime()
            }
        } catch {
            logger.error("swift-build backend startup failed: \(error)")
            writeStderr("xcode-bsp: swift-build backend startup failed: \(error)\n")
            throw error
        }

        transport = startup.transport
        service = startup.service
        session = startup.session

        startup.transport.start(
            receiveHandler: startup.buildServer,
            closeHandler: { [weak self] in
                await self?.shutdownIfNeeded(exitCode: nil)
            }
        )

        RunLoop.current.run()

        try waitForAsync { [self] in
            await shutdownIfNeeded(exitCode: nil)
        }
    }
}

extension SwiftBuildServerBackend {
    fileprivate struct StartupRuntime {
        let transport: LanguageServerProtocolTransport.JSONRPCConnection
        let service: SWBBuildService
        let session: SWBBuildServiceSession
        let buildServer: any MessageHandler
    }

    fileprivate func createRuntime() async throws -> StartupRuntime {
        let containerPath = try resolvedWorkspaceContainerPath()
        logger.debug("swift-build resolved container path: \(containerPath)")

        logger.debug("swift-build creating service (connectionMode: inProcessStatic)")
        let service = try await SWBBuildService(
            connectionMode: .inProcessStatic(swiftbuildServiceEntryPoint)
        )
        let sessionName =
            "\(URL(filePath: FileManager.default.currentDirectoryPath).lastPathComponent)-xcode-bsp"
        let swiftBuildCacheDir = cacheDir.appending(component: "swift-build-service")
        if FileManager.default.fileExists(atPath: swiftBuildCacheDir.path()) == false {
            try FileManager.default.createDirectory(
                at: swiftBuildCacheDir, withIntermediateDirectories: true)
        }
        let developerPath = resolvedDeveloperPath()
        logger.debug(
            "swift-build createSession(name: \(sessionName), developerPath: \(developerPath ?? "nil"))"
        )

        let (sessionResult, diagnostics) = await service.createSession(
            name: sessionName,
            developerPath: developerPath,
            cachePath: swiftBuildCacheDir.path(),
            inferiorProductsPath: nil,
            environment: nil
        )

        for diagnostic in diagnostics {
            logger.debug("swift-build session diagnostic: \(String(describing: diagnostic))")
        }

        do {
            let session = try sessionResult.get()
            logger.debug("swift-build session created (uid: \(session.uid))")
            let buildRequest = try await makeBuildRequest(
                containerPath: containerPath, session: session)
            let transport = LanguageServerProtocolTransport.JSONRPCConnection(
                name: "xcode-bsp-swiftbuild",
                protocol: MessageRegistry.bspProtocol,
                receiveFD: .standardInput,
                sendFD: .standardOutput
            )
            logger.debug("swift-build using SWBBuildServer containerPath mode")
            let buildServer = SWBBuildServer(
                session: session,
                containerPath: containerPath,
                buildRequest: buildRequest,
                behaviorOptions: .init(
                    autoPrepareBeforeSourceKitOptions: true,
                    deduplicateBuildLogNotifications: true
                ),
                connectionToClient: transport,
                exitHandler: { [weak self] code in
                    await self?.shutdownIfNeeded(exitCode: code)
                }
            )
            let receiveHandler: any MessageHandler = buildServer
            logger.debug("swift-build response interceptor disabled (using native SwiftBuild sourceKitOptions)")

            logger.debug(
                """
                swift-build backend initialized \
                (containerPath: \(containerPath), configuredTargets: \(buildRequest.configuredTargets.count), \
                configuration: \(buildRequest.parameters.configurationName ?? "nil"))
                """
            )
            return StartupRuntime(
                transport: transport,
                service: service,
                session: session,
                buildServer: receiveHandler
            )
        } catch {
            await service.close()
            throw error
        }
    }

    fileprivate func makeBuildRequest(
        containerPath: String,
        session: SWBBuildServiceSession
    ) async throws -> SWBBuildRequest {
        logger.debug(
            "swift-build loading workspace via containerPath for request construction: \(containerPath)"
        )
        try await session.loadWorkspace(containerPath: containerPath)
        logger.debug("swift-build workspace loaded from containerPath")
        logger.debug("swift-build reading workspace info for request construction")
        let workspaceInfo = try await session.workspaceInfo()
        logger.debug(
            "swift-build workspace info loaded (targets: \(workspaceInfo.targetInfos.count))")

        var parameters = SWBBuildParameters()
        if parameters.configurationName == nil {
            parameters.configurationName = "Debug"
        }
        parameters.action = "build"
        if let runDestination = defaultHostRunDestination() {
            parameters.activeRunDestination = runDestination
            parameters.activeArchitecture = runDestination.targetArchitecture
            logger.debug(
                "swift-build build request configured host run destination (targetArchitecture: \(runDestination.targetArchitecture))"
            )
        } else {
            logger.warning(
                "swift-build build request could not determine host run destination; leaving activeRunDestination unset"
            )
        }

        let seedConfiguredTargets = configuredTargets(
            from: workspaceInfo,
            requestedSchemeNames: config.activeSchemes,
            parameters: parameters
        )
        let configuredTargets = await expandConfiguredTargetsWithDependencyClosure(
            session: session,
            configuredTargets: seedConfiguredTargets,
            parameters: parameters
        )

        var request = SWBBuildRequest()
        request.parameters = parameters
        request.useImplicitDependencies = true
        request.configuredTargets = configuredTargets
        request.continueBuildingAfterErrors = true
        request.dependencyScope = .workspace
        request.schemeCommand = nil

        logger.debug(
            """
            swift-build request prepared \
            (configuredTargets: \(configuredTargets.count), seedTargets: \(seedConfiguredTargets.count), \
            useImplicitDependencies: \(request.useImplicitDependencies), \
            dependencyScope: \(request.dependencyScope.rawValue), schemeCommand: \(request.schemeCommand?.rawValue ?? "nil"), \
            configuration: \(parameters.configurationName ?? "nil"), \
            activeRunDestination: \(parameters.activeRunDestination != nil), activeSchemesCount: \(config.activeSchemes.count))
            """
        )
        return request
    }

    fileprivate func configuredTargets(
        from workspaceInfo: SWBWorkspaceInfo,
        requestedSchemeNames: [String],
        parameters: SWBBuildParameters
    ) -> [SWBConfiguredTarget] {
        return workspaceInfo.targetInfos
            .map { SWBConfiguredTarget(guid: $0.guid, parameters: parameters) }
    }

    fileprivate func nonDynamicTargetInfos(from workspaceInfo: SWBWorkspaceInfo) -> [SWBTargetInfo]
    {
        let dynamicVariantGUIDs = Set(
            workspaceInfo.targetInfos.compactMap(\.dynamicTargetVariantGuid))
        return workspaceInfo.targetInfos.filter { dynamicVariantGUIDs.contains($0.guid) == false }
    }

    fileprivate func defaultHostRunDestination() -> SWBRunDestinationInfo? {
        let systemInfo: SWBSystemInfo
        do {
            systemInfo = try .default()
        } catch {
            logger.error(
                "swift-build failed to compute host system info for run destination: \(error)")
            return nil
        }

        let arch = systemInfo.nativeArchitecture
        let supportedArchitectures: [String]
        switch arch {
        case "arm64":
            supportedArchitectures = ["arm64", "x86_64"]
        case "x86_64":
            supportedArchitectures = ["x86_64h", "x86_64"]
        default:
            supportedArchitectures = [arch]
        }

        return SWBRunDestinationInfo(
            platform: "macosx",
            sdk: "macosx",
            sdkVariant: "macos",
            targetArchitecture: arch,
            supportedArchitectures: supportedArchitectures,
            disableOnlyActiveArch: false
        )
    }

    fileprivate func expandConfiguredTargetsWithDependencyClosure(
        session: SWBBuildServiceSession,
        configuredTargets: [SWBConfiguredTarget],
        parameters: SWBBuildParameters
    ) async -> [SWBConfiguredTarget] {
        let seedGUIDs = configuredTargets.map(\.guid)
        guard seedGUIDs.isEmpty == false else {
            logger.error(
                "swift-build request has no seed targets; dependency closure expansion skipped")
            return configuredTargets
        }

        do {
            let closureGUIDs = try await session.computeDependencyClosure(
                targetGUIDs: seedGUIDs,
                buildParameters: parameters,
                includeImplicitDependencies: true,
                dependencyScope: .workspace
            )

            guard closureGUIDs.isEmpty == false else {
                logger.error(
                    "swift-build dependency closure returned empty result; using seed targets")
                return configuredTargets
            }

            var orderedGUIDs = closureGUIDs

            do {
                let dependencyGraph = try await session.computeDependencyGraph(
                    targetGUIDs: closureGUIDs.map(SWBTargetGUID.init(rawValue:)),
                    buildParameters: parameters,
                    includeImplicitDependencies: true,
                    dependencyScope: .workspace
                )
                let graphTargetGUIDs = Set(dependencyGraph.keys.map(\.rawValue))
                    .union(dependencyGraph.values.flatMap { $0.map(\.rawValue) })
                let knownGUIDs = Set(orderedGUIDs)
                let missingPackageTargetGUIDs = graphTargetGUIDs
                    .filter { $0.hasPrefix("PACKAGE-TARGET:") && knownGUIDs.contains($0) == false }
                    .sorted()

                if missingPackageTargetGUIDs.isEmpty == false {
                    orderedGUIDs.append(contentsOf: missingPackageTargetGUIDs)
                    logger.debug(
                        "swift-build dependency graph added missing package targets to configured target seeds (count: \(missingPackageTargetGUIDs.count), targets: \(missingPackageTargetGUIDs))"
                    )
                }
            } catch {
                logger.error(
                    "swift-build dependency graph expansion failed while augmenting configured targets: \(error)"
                )
            }

            let expanded = orderedGUIDs.map {
                SWBConfiguredTarget(guid: $0, parameters: parameters)
            }
            logger.debug(
                "swift-build dependency closure expanded configured targets (seed: \(seedGUIDs.count), closure: \(closureGUIDs.count), final: \(expanded.count))"
            )
            return expanded
        } catch {
            logger.error("swift-build dependency closure failed; using seed targets: \(error)")
            return configuredTargets
        }
    }

    fileprivate func resolvedWorkspaceContainerPath() throws -> String {
        guard
            let configuredPath = config.workspaceContainerPath?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            configuredPath.isEmpty == false
        else {
            throw StartupError.missingWorkspaceContainerPath
        }

        let cwd = URL(filePath: FileManager.default.currentDirectoryPath)
        let resolvedURL = URL(filePath: configuredPath, relativeTo: cwd)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let path = resolvedURL.path()

        guard FileManager.default.fileExists(atPath: path) else {
            throw StartupError.workspaceContainerDoesNotExist(path)
        }

        let lowercasedExtension = resolvedURL.pathExtension.lowercased()
        guard lowercasedExtension == "xcodeproj" || lowercasedExtension == "xcworkspace" else {
            throw StartupError.invalidWorkspaceContainer(path)
        }

        return path
    }

    fileprivate func shutdownIfNeeded(exitCode: Int?) async {
        let shouldShutdown = beginShutdown(exitCode: exitCode)
        guard shouldShutdown else {
            return
        }

        if let session {
            do {
                try await session.close()
            } catch {
                logger.error("swift-build session close failed: \(error)")
            }
        }

        if let service {
            await service.close()
        }

        transport?.close()
        stopRunLoop()
    }

    fileprivate func beginShutdown(exitCode: Int?) -> Bool {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }

        guard didShutdown == false else {
            return false
        }

        didShutdown = true
        return true
    }

    fileprivate func stopRunLoop() {
        DispatchQueue.main.async {
            CFRunLoopStop(CFRunLoopGetMain())
        }
    }

    fileprivate func resolvedDeveloperPath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let value = environment["DEVELOPER_DIR"]?.trimmingCharacters(
            in: .whitespacesAndNewlines),
            value.isEmpty == false
        {
            return value
        }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(filePath: "/usr/bin/xcode-select")
        task.arguments = ["-p"]
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                return nil
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let text, text.isEmpty == false else {
                return nil
            }
            return text
        } catch {
            return nil
        }
    }

    fileprivate func writeStderr(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        try? FileHandle.standardError.write(contentsOf: data)
    }

    fileprivate func waitForAsync<T>(_ operation: @escaping @Sendable () async throws -> T) throws
        -> T
    {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedBox<Swift.Result<T, Error>>()

        Task {
            do {
                let value = try await operation()
                resultBox.set(.success(value))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        return try resultBox.get()!.get()
    }

    fileprivate final class LockedBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T?

        func set(_ value: T) {
            lock.lock()
            defer { lock.unlock() }
            self.value = value
        }

        func get() -> T? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    fileprivate final class SourceKitOptionsAugmentingMessageHandler: MessageHandler, @unchecked Sendable {
        private let base: any MessageHandler
        private let logger: Logger
        private let workspaceRootURL: URL
        private let configurationName: String
        private let lock = NSLock()
        private var cachedBuildTargetsByID: [String: BuildTarget] = [:]
        private var cachedSourceFilePathsByTargetID: [String: [String]] = [:]
        private var cachedTargetIDsBySourceFilePath: [String: Set<String>] = [:]

        init(
            base: any MessageHandler,
            logger: Logger,
            workspaceRootURL: URL,
            configurationName: String
        ) {
            self.base = base
            self.logger = logger
            self.workspaceRootURL = workspaceRootURL.standardizedFileURL
            self.configurationName = configurationName
        }

        func handle(_ notification: some NotificationType) {
            switch notification {
            case is OnBuildInitializedNotification, is OnBuildExitNotification:
                clearCaches(reason: "\(type(of: notification))")
            case is OnWatchedFilesDidChangeNotification:
                clearCaches(reason: "\(type(of: notification))")
            default:
                break
            }

            base.handle(notification)
        }

        func handle<Request>(
            _ request: Request,
            id: RequestID,
            reply: @Sendable @escaping (LSPResult<Request.Response>) -> Void
        ) where Request: RequestType {
            if request is BuildShutdownRequest {
                clearCaches(reason: "BuildShutdownRequest")
            }

            if let buildTargetsRequest = request as? WorkspaceBuildTargetsRequest {
                logger.debug(
                    "swift-build intercept workspace/buildTargets (id: \(String(describing: id)))")
                base.handle(buildTargetsRequest, id: id) { [weak self, logger] result in
                    if case .success(let response) = result {
                        self?.cacheWorkspaceBuildTargets(response, requestID: id)
                    }
                    Self.logWorkspaceBuildTargetsReply(result, requestID: id, logger: logger)
                    reply(result as! LSPResult<Request.Response>)
                }
                return
            }

            if let sourcesRequest = request as? BuildTargetSourcesRequest {
                logger.debug(
                    "swift-build intercept buildTarget/sources (id: \(String(describing: id)), targets: \(sourcesRequest.targets.count))"
                )
                base.handle(sourcesRequest, id: id) { [weak self, logger] result in
                    if case .success(let response) = result {
                        self?.cacheBuildTargetSources(response, requestID: id)
                    }
                    Self.logBuildTargetSourcesReply(result, requestID: id, logger: logger)
                    reply(result as! LSPResult<Request.Response>)
                }
                return
            }

            guard let sourceKitRequest = request as? TextDocumentSourceKitOptionsRequest else {
                base.handle(request, id: id, reply: reply)
                return
            }

            logger.debug(
                """
                swift-build sourceKitOptions augmentation intercept \
                (id: \(String(describing: id)), file: \(sourceKitRequest.textDocument.uri.stringValue), \
                target: \(sourceKitRequest.target), language: \(sourceKitRequest.language.rawValue))
                """
            )
            base.handle(sourceKitRequest, id: id) { result in
                let processed = self.processSourceKitOptionsResult(
                    result,
                    request: sourceKitRequest,
                    requestID: id
                )
                reply(processed as! LSPResult<Request.Response>)
            }
        }

        private func clearCaches(reason: String) {
            lock.lock()
            let cachedTargetsCount = cachedBuildTargetsByID.count
            let cachedSourcesTargetsCount = cachedSourceFilePathsByTargetID.count
            let cachedReverseMapCount = cachedTargetIDsBySourceFilePath.count
            cachedBuildTargetsByID.removeAll()
            cachedSourceFilePathsByTargetID.removeAll()
            cachedTargetIDsBySourceFilePath.removeAll()
            lock.unlock()

            if cachedTargetsCount > 0 || cachedSourcesTargetsCount > 0 || cachedReverseMapCount > 0 {
                logger.debug(
                    """
                    swift-build sourceKit augmentation cache cleared \
                    (\(reason), cachedBuildTargets: \(cachedTargetsCount), \
                    cachedSourceTargets: \(cachedSourcesTargetsCount), cachedSourceFiles: \(cachedReverseMapCount))
                    """
                )
            }
        }

        private func cacheWorkspaceBuildTargets(
            _ response: WorkspaceBuildTargetsRequest.Response,
            requestID: RequestID
        ) {
            let targetsByID = Dictionary(
                uniqueKeysWithValues: response.targets.map { ($0.id.uri.stringValue, $0) }
            )
            let edgeCount = response.targets.reduce(0) { $0 + $1.dependencies.count }
            let packageTargets = response.targets.filter { target in
                (targetGUID(from: target.id) ?? "").hasPrefix("PACKAGE-TARGET:")
            }
            let packageTargetSummaries = packageTargets
                .prefix(6)
                .map { target in
                    let targetGUID = self.targetGUID(from: target.id) ?? "<unknown>"
                    return "\(target.displayName ?? "<nil>")<\(targetGUID)>"
                }
                .joined(separator: ", ")

            lock.lock()
            cachedBuildTargetsByID = targetsByID
            lock.unlock()

            logger.debug(
                """
                swift-build workspace/buildTargets cache updated \
                (id: \(String(describing: requestID)), targets: \(targetsByID.count), dependencyEdges: \(edgeCount), \
                packageTargets: \(packageTargets.count), samplePackageTargets: [\(packageTargetSummaries)])
                """
            )
        }

        private func cacheBuildTargetSources(
            _ response: BuildTargetSourcesRequest.Response,
            requestID: RequestID
        ) {
            var updatedTargetIDs: [String] = []
            var totalFilesAdded = 0

            lock.lock()
            for item in response.items {
                let targetID = item.target.uri.stringValue
                let filePaths = item.sources.compactMap { source -> String? in
                    guard source.kind == .file else {
                        return nil
                    }
                    return source.uri.fileURL?.standardizedFileURL.path()
                }
                cachedSourceFilePathsByTargetID[targetID] = filePaths
                updatedTargetIDs.append(targetID)
                totalFilesAdded += filePaths.count
            }

            var reverse = [String: Set<String>]()
            reverse.reserveCapacity(
                cachedSourceFilePathsByTargetID.values.reduce(0) { $0 + $1.count })
            for (targetID, filePaths) in cachedSourceFilePathsByTargetID {
                for filePath in filePaths {
                    reverse[filePath, default: []].insert(targetID)
                }
            }
            cachedTargetIDsBySourceFilePath = reverse

            let localPackageSourceTargets = cachedSourceFilePathsByTargetID.keys.filter { targetID in
                guard let target = cachedBuildTargetsByID[targetID] else {
                    return false
                }
                guard let targetGUID = targetGUID(from: target.id),
                    targetGUID.hasPrefix("PACKAGE-TARGET:")
                else {
                    return false
                }
                let filePaths = cachedSourceFilePathsByTargetID[targetID] ?? []
                let workspaceRootPath = normalizedPath(workspaceRootURL)
                let workspaceRootPrefix = workspaceRootPath == "/" ? "/" : workspaceRootPath + "/"
                return filePaths.contains { filePath in
                    let normalizedFilePath = normalizedPath(filePath)
                    return normalizedFilePath == workspaceRootPath
                        || normalizedFilePath.hasPrefix(workspaceRootPrefix)
                }
            }.count
            let totalCachedSourceTargets = cachedSourceFilePathsByTargetID.count
            let totalCachedSourceFiles = cachedTargetIDsBySourceFilePath.count
            lock.unlock()

            logger.debug(
                """
                swift-build buildTarget/sources cache updated \
                (id: \(String(describing: requestID)), updatedTargets: \(updatedTargetIDs.count), \
                updatedFileSources: \(totalFilesAdded), cachedSourceTargets: \(totalCachedSourceTargets), \
                cachedSourceFiles: \(totalCachedSourceFiles), localPackageSourceTargets: \(localPackageSourceTargets))
                """
            )
        }

        private func processSourceKitOptionsResult(
            _ result: LSPResult<TextDocumentSourceKitOptionsRequest.Response>,
            request: TextDocumentSourceKitOptionsRequest,
            requestID: RequestID
        ) -> LSPResult<TextDocumentSourceKitOptionsRequest.Response> {
            let processed: LSPResult<TextDocumentSourceKitOptionsRequest.Response>
            switch result {
            case .failure:
                processed = result
            case .success(let response):
                guard let response else {
                    processed = result
                    break
                }
                let augmentedResponse = augmentSourceKitOptionsResponse(
                    response,
                    request: request,
                    requestID: requestID
                )
                let wrapped: TextDocumentSourceKitOptionsRequest.Response = augmentedResponse
                processed = .success(wrapped)
            }

            logSourceKitOptionsReply(processed, request: request, requestID: requestID)
            return processed
        }

        private func augmentSourceKitOptionsResponse(
            _ response: TextDocumentSourceKitOptionsResponse,
            request: TextDocumentSourceKitOptionsRequest,
            requestID: RequestID
        ) -> TextDocumentSourceKitOptionsResponse {
            let sourceTargetID = request.target.uri.stringValue
            let sourceFilePath = request.textDocument.uri.fileURL?.standardizedFileURL.path()

            let (sourceTarget, sourceTargetDependencies, cachedSourceFilePathsByTargetIDSnapshot) = snapshotForAugmentation(
                sourceTargetID: sourceTargetID
            )

            guard let sourceTarget else {
                logger.debug(
                    """
                    swift-build sourceKitOptions augmentation skipped \
                    (id: \(String(describing: requestID)), reason: no cached workspace/buildTargets entry for source target, \
                    target: \(request.target))
                    """
                )
                return response
            }

            if sourceTargetDependencies.isEmpty {
                logger.debug(
                    """
                    swift-build sourceKitOptions augmentation skipped \
                    (id: \(String(describing: requestID)), reason: source target has no BSP dependencies, \
                    target: \(request.target))
                    """
                )
                return response
            }

            let localPackageRoots = sourceTargetDependencies.compactMap { dependencyID -> LocalPackageDependencyAugmentation? in
                guard let dependencyTargetGUID = targetGUID(from: dependencyID),
                    dependencyTargetGUID.hasPrefix("PACKAGE-TARGET:")
                else {
                    return nil
                }

                let dependencyTargetID = dependencyID.uri.stringValue
                guard let dependencySourceFilePaths = cachedSourceFilePathsByTargetIDSnapshot[dependencyTargetID],
                    dependencySourceFilePaths.isEmpty == false
                else {
                    logger.debug(
                        """
                        swift-build sourceKitOptions augmentation dependency skipped \
                        (id: \(String(describing: requestID)), reason: no cached sources for dependency target, \
                        sourceTarget: \(sourceTargetID), dependencyTarget: \(dependencyTargetID))
                        """
                    )
                    return nil
                }

                guard let packageRootURL = localPackageRootURL(fromSourceFilePaths: dependencySourceFilePaths)
                else {
                    logger.debug(
                        """
                        swift-build sourceKitOptions augmentation dependency skipped \
                        (id: \(String(describing: requestID)), reason: dependency package root unsupported for augmentation, \
                        sourceTarget: \(sourceTargetID), dependencyTarget: \(dependencyTargetID))
                        """
                    )
                    return nil
                }

                let dependencyDisplayName =
                    cachedBuildTargetsByIDSnapshotValue(for: dependencyTargetID)?.displayName ?? "<nil>"

                var frameworkPaths: [String] = []
                let packageFrameworksPath = packageRootURL
                    .appending(component: "build")
                    .appending(component: configurationName)
                    .appending(component: "PackageFrameworks")
                    .path()
                if FileManager.default.fileExists(atPath: packageFrameworksPath) {
                    frameworkPaths.append(packageFrameworksPath)
                }

                var includePaths: [String] = []
                let packageBuildConfigurationPath = packageRootURL
                    .appending(component: "build")
                    .appending(component: configurationName)
                    .path()
                if FileManager.default.fileExists(atPath: packageBuildConfigurationPath) {
                    includePaths.append(packageBuildConfigurationPath)
                }

                if frameworkPaths.isEmpty && includePaths.isEmpty {
                    logger.debug(
                        """
                        swift-build sourceKitOptions augmentation dependency skipped \
                        (id: \(String(describing: requestID)), reason: no package build search paths exist, \
                        sourceTarget: \(sourceTargetID), dependencyTarget: \(dependencyTargetID), \
                        packageRoot: \(packageRootURL.path()))
                        """
                    )
                    return nil
                }

                return LocalPackageDependencyAugmentation(
                    dependencyTargetID: dependencyTargetID,
                    dependencyTargetGUID: dependencyTargetGUID,
                    displayName: dependencyDisplayName,
                    packageRootPath: packageRootURL.path(),
                    frameworkPaths: frameworkPaths,
                    includePaths: includePaths
                )
            }

            if localPackageRoots.isEmpty {
                logger.debug(
                    """
                    swift-build sourceKitOptions augmentation skipped \
                    (id: \(String(describing: requestID)), reason: no package dependency paths to add, \
                    file: \(sourceFilePath ?? request.textDocument.uri.stringValue), sourceTarget: \(sourceTargetID), \
                    deps: \(sourceTargetDependencies.count))
                    """
                )
                return response
            }

            let existingSearchPaths = compilerSearchPaths(from: response.compilerArguments)
            var existingFrameworkPaths = existingSearchPaths.frameworkPaths
            var existingIncludePaths = existingSearchPaths.includePaths
            var addedArguments: [String] = []
            var augmentedArguments = response.compilerArguments

            func appendPath(flag: String, path: String, existingSet: inout Set<String>) {
                guard existingSet.contains(path) == false else {
                    return
                }
                existingSet.insert(path)
                augmentedArguments.append(flag)
                augmentedArguments.append(path)
                addedArguments.append("\(flag) \(path)")
            }

            for package in localPackageRoots.sorted(by: { $0.packageRootPath < $1.packageRootPath }) {
                for path in package.frameworkPaths {
                    appendPath(flag: "-F", path: path, existingSet: &existingFrameworkPaths)
                }
                for path in package.includePaths {
                    appendPath(flag: "-I", path: path, existingSet: &existingIncludePaths)
                }
            }

            guard addedArguments.isEmpty == false else {
                logger.debug(
                    """
                    swift-build sourceKitOptions augmentation no-op \
                    (id: \(String(describing: requestID)), reason: candidate paths already present, \
                    file: \(sourceFilePath ?? request.textDocument.uri.stringValue), sourceTarget: \(sourceTargetID), \
                    localPackages: \(localPackageRoots.map(\.packageRootPath).sorted()))
                    """
                )
                return response
            }

            let localPackageDetails = localPackageRoots
                .map {
                    "\($0.displayName)<\($0.dependencyTargetGUID)> root=\($0.packageRootPath)"
                }
                .sorted()
            logger.debug(
                """
                swift-build sourceKitOptions augmentation applied \
                (id: \(String(describing: requestID)), file: \(sourceFilePath ?? request.textDocument.uri.stringValue), \
                sourceTarget: \(sourceTarget.displayName ?? "<nil>")<\(targetGUID(from: sourceTarget.id) ?? "<unknown>")>, \
                localPackages: \(localPackageDetails), added: \(addedArguments), \
                beforePaths: \(resolvedCompilerPathsSummary(response.compilerArguments)), \
                afterPaths: \(resolvedCompilerPathsSummary(augmentedArguments)))
                """
            )

            return TextDocumentSourceKitOptionsResponse(
                compilerArguments: augmentedArguments,
                workingDirectory: response.workingDirectory
            )
        }

        private struct LocalPackageDependencyAugmentation {
            let dependencyTargetID: String
            let dependencyTargetGUID: String
            let displayName: String
            let packageRootPath: String
            let frameworkPaths: [String]
            let includePaths: [String]
        }

        private func snapshotForAugmentation(
            sourceTargetID: String
        ) -> (BuildTarget?, [BuildTargetIdentifier], [String: [String]]) {
            lock.lock()
            let sourceTarget = cachedBuildTargetsByID[sourceTargetID]
            let dependencies = cachedBuildTargetsByID[sourceTargetID]?.dependencies ?? []
            let sourcesSnapshot = cachedSourceFilePathsByTargetID
            lock.unlock()
            return (sourceTarget, dependencies, sourcesSnapshot)
        }

        private func cachedBuildTargetsByIDSnapshotValue(for targetID: String) -> BuildTarget? {
            lock.lock()
            let target = cachedBuildTargetsByID[targetID]
            lock.unlock()
            return target
        }

        private func compilerSearchPaths(from args: [String]) -> (includePaths: Set<String>, frameworkPaths: Set<String>) {
            var includePaths: [String] = []
            var frameworkPaths: [String] = []
            var isystemPaths: [String] = []
            var moduleMapFiles: [String] = []

            var index = 0
            while index < args.count {
                let arg = args[index]
                if arg == "-Xcc", index + 1 < args.count {
                    let consumed = consumeSearchPathArguments(
                        args,
                        startIndex: index + 1,
                        isXccWrapped: true,
                        includePaths: &includePaths,
                        frameworkPaths: &frameworkPaths,
                        isystemPaths: &isystemPaths,
                        moduleMapFiles: &moduleMapFiles
                    )
                    if consumed > 0 {
                        index += 1 + consumed
                        continue
                    }
                }

                let consumed = consumeSearchPathArguments(
                    args,
                    startIndex: index,
                    isXccWrapped: false,
                    includePaths: &includePaths,
                    frameworkPaths: &frameworkPaths,
                    isystemPaths: &isystemPaths,
                    moduleMapFiles: &moduleMapFiles
                )
                if consumed > 0 {
                    index += consumed
                } else {
                    index += 1
                }
            }

            return (Set(includePaths), Set(frameworkPaths))
        }

        private func targetGUID(from target: BuildTargetIdentifier) -> String? {
            guard
                let components = URLComponents(string: target.uri.stringValue),
                let targetGUID = components.queryItems?.last(where: { $0.name == "targetGUID" })?.value
            else {
                return nil
            }
            return targetGUID
        }

        private func localPackageRootURL(fromSourceFilePaths sourceFilePaths: [String]) -> URL? {
            for sourceFilePath in sourceFilePaths {
                guard sourceFilePath.isEmpty == false else {
                    continue
                }
                let sourceFileURL = URL(filePath: sourceFilePath)
                if let packageRoot = packageRootURL(containing: sourceFileURL) {
                    return packageRoot
                }
            }
            return nil
        }

        private func packageRootURL(containing sourceFileURL: URL) -> URL? {
            var current = sourceFileURL.deletingLastPathComponent().standardizedFileURL
            while true {
                let packageManifestURL = current.appending(component: "Package.swift")
                if FileManager.default.fileExists(atPath: packageManifestURL.path()) {
                    return isSupportedPackageRootForAugmentation(current) ? current : nil
                }

                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent.path() == current.path() {
                    return nil
                }
                current = parent
            }
        }

        private func isSupportedPackageRootForAugmentation(_ packageRootURL: URL) -> Bool {
            if isDescendantOrEqual(packageRootURL, of: workspaceRootURL) {
                return true
            }
            return isSourcePackagesCheckoutPackage(packageRootURL)
        }

        private func isSourcePackagesCheckoutPackage(_ packageRootURL: URL) -> Bool {
            let path = normalizedPath(packageRootURL)
            return path.localizedCaseInsensitiveContains("/SourcePackages/checkouts/")
        }

        private func isDescendantOrEqual(_ candidate: URL, of root: URL) -> Bool {
            let candidatePath = normalizedPath(candidate)
            let rootPath = normalizedPath(root)
            if candidatePath == rootPath {
                return true
            }
            let rootPrefix = rootPath == "/" ? "/" : rootPath + "/"
            return candidatePath.hasPrefix(rootPrefix)
        }

        private func normalizedPath(_ url: URL) -> String {
            normalizedPath(url.standardizedFileURL.path())
        }

        private func normalizedPath(_ path: String) -> String {
            guard path.count > 1 else {
                return path
            }
            return path.hasSuffix("/") ? String(path.dropLast()) : path
        }

        private static func logWorkspaceBuildTargetsReply(
            _ result: LSPResult<WorkspaceBuildTargetsRequest.Response>,
            requestID: RequestID,
            logger: Logger
        ) {
            switch result {
            case .failure(let error):
                logger.error(
                    "swift-build workspace/buildTargets reply failed (id: \(String(describing: requestID)), error: \(error))"
                )
            case .success(let response):
                let targets = response.targets
                let targetCount = targets.count
                let edgeCount = targets.reduce(0) { $0 + $1.dependencies.count }
                let targetsWithDependencies = targets.reduce(0) { count, target in
                    count + (target.dependencies.isEmpty ? 0 : 1)
                }
                let zeroDependencyTargets = targetCount - targetsWithDependencies

                let topTargetsByDependencyCount =
                    targets
                    .sorted { lhs, rhs in
                        if lhs.dependencies.count == rhs.dependencies.count {
                            return lhs.id.uri.stringValue < rhs.id.uri.stringValue
                        }
                        return lhs.dependencies.count > rhs.dependencies.count
                    }
                    .prefix(5)
                    .map { target in
                        let displayName = target.displayName ?? "<nil>"
                        return "\(displayName):\(target.dependencies.count)"
                    }
                    .joined(separator: ", ")

                logger.debug(
                    """
                    swift-build workspace/buildTargets reply \
                    (id: \(String(describing: requestID)), targets: \(targetCount), dependencyEdges: \(edgeCount), \
                    targetsWithDependencies: \(targetsWithDependencies), zeroDependencyTargets: \(zeroDependencyTargets), \
                    topDependencyCounts: [\(topTargetsByDependencyCount)])
                    """
                )

                let displayNameByTargetURI = Dictionary(
                    uniqueKeysWithValues: targets.map { target in
                        (target.id.uri.stringValue, target.displayName ?? "<nil>")
                    }
                )
                let dependencyPairs =
                    targets
                    .sorted { lhs, rhs in
                        let lhsName = lhs.displayName ?? ""
                        let rhsName = rhs.displayName ?? ""
                        if lhsName == rhsName {
                            return lhs.id.uri.stringValue < rhs.id.uri.stringValue
                        }
                        return lhsName < rhsName
                    }
                    .map { target -> String in
                        let targetName = target.displayName ?? "<nil>"
                        let dependencyList = target.dependencies
                            .sorted { $0.uri.stringValue < $1.uri.stringValue }
                            .map { dependencyID -> String in
                                let uri = dependencyID.uri.stringValue
                                let name = displayNameByTargetURI[uri] ?? "<unknown>"
                                return "\(name)<\(uri)>"
                            }
                            .joined(separator: ", ")
                        return "\(targetName)<\(target.id.uri.stringValue)> -> [\(dependencyList)]"
                    }
                    .joined(separator: " | ")

                logger.debug(
                    """
                    swift-build workspace/buildTargets dependency pairs \
                    (id: \(String(describing: requestID)), pairs: \(dependencyPairs))
                    """
                )

                if edgeCount == 0, targetCount > 0 {
                    let sampleTargets =
                        targets
                        .prefix(5)
                        .map { target in
                            let displayName = target.displayName ?? "<nil>"
                            return "\(displayName)=\(target.id.uri.stringValue)"
                        }
                        .joined(separator: ", ")
                    logger.warning(
                        """
                        swift-build workspace/buildTargets returned zero dependency edges \
                        (id: \(String(describing: requestID)), sampleTargets: [\(sampleTargets)])
                        """
                    )
                }
            }
        }

        private static func logBuildTargetSourcesReply(
            _ result: LSPResult<BuildTargetSourcesRequest.Response>,
            requestID: RequestID,
            logger: Logger
        ) {
            switch result {
            case .failure(let error):
                logger.error(
                    "swift-build buildTarget/sources reply failed (id: \(String(describing: requestID)), error: \(error))"
                )
            case .success(let response):
                let items = response.items
                let itemCount = items.count
                let sourceCount = items.reduce(0) { $0 + $1.sources.count }
                let directorySourceItems = items.reduce(0) { count, item in
                    count
                        + item.sources.reduce(0) { innerCount, source in
                            innerCount + (source.kind == .directory ? 1 : 0)
                        }
                }

                logger.debug(
                    """
                    swift-build buildTarget/sources reply \
                    (id: \(String(describing: requestID)), items: \(itemCount), sources: \(sourceCount), \
                    directoryEntries: \(directorySourceItems))
                    """
                )

                for (index, item) in items.enumerated() {
                    let fileSourceCount = item.sources.reduce(0) { count, source in
                        count + (source.kind == .file ? 1 : 0)
                    }
                    let directoryCount = item.sources.reduce(0) { count, source in
                        count + (source.kind == .directory ? 1 : 0)
                    }
                    let sampleSources = item.sources
                        .prefix(3)
                        .map { source in
                            "\(source.kind.rawValue):\(source.uri.stringValue)"
                        }
                        .joined(separator: ", ")

                    logger.debug(
                        """
                        swift-build buildTarget/sources item \
                        (id: \(String(describing: requestID)), index: \(index), target: \(item.target.uri.stringValue), \
                        sources: \(item.sources.count), fileSources: \(fileSourceCount), \
                        directorySources: \(directoryCount), sample: [\(sampleSources)])
                        """
                    )
                }
            }
        }

        private func logSourceKitOptionsReply(
            _ result: LSPResult<TextDocumentSourceKitOptionsRequest.Response>,
            request: TextDocumentSourceKitOptionsRequest,
            requestID: RequestID
        ) {
            switch result {
            case .failure(let error):
                logger.error(
                    """
                    swift-build sourceKitOptions reply failed \
                    (id: \(String(describing: requestID)), file: \(request.textDocument.uri.stringValue), \
                    target: \(request.target), error: \(error))
                    """
                )
            case .success(let response):
                guard let response else {
                    logger.debug(
                        """
                        swift-build sourceKitOptions reply nil \
                        (id: \(String(describing: requestID)), file: \(request.textDocument.uri.stringValue), \
                        target: \(request.target))
                        """
                    )
                    return
                }

                logger.debug(
                    """
                    swift-build sourceKitOptions reply success \
                    (id: \(String(describing: requestID)), file: \(request.textDocument.uri.stringValue), \
                    target: \(request.target), args: \(response.compilerArguments.count), \
                    summary: \(compilerArgumentsSummary(response.compilerArguments)), \
                    resolvedPaths: \(resolvedCompilerPathsSummary(response.compilerArguments)), \
                    workingDirectory: \(response.workingDirectory ?? "nil"))
                    """
                )
                logSourceKitOptionsDependencyCoverage(
                    response: response,
                    request: request,
                    requestID: requestID
                )
            }
        }

        private func logSourceKitOptionsDependencyCoverage(
            response: TextDocumentSourceKitOptionsResponse,
            request: TextDocumentSourceKitOptionsRequest,
            requestID: RequestID
        ) {
            let sourceTargetID = request.target.uri.stringValue
            let (sourceTarget, sourceTargetDependencies, cachedSourceFilePathsByTargetIDSnapshot) =
                snapshotForAugmentation(sourceTargetID: sourceTargetID)

            guard let sourceTarget else {
                return
            }

            let searchPaths = compilerSearchPaths(from: response.compilerArguments)
            let includePaths = searchPaths.includePaths
            let frameworkPaths = searchPaths.frameworkPaths

            let dependencyCoverage = sourceTargetDependencies.compactMap { dependencyID -> String? in
                guard let dependencyTargetGUID = targetGUID(from: dependencyID),
                    dependencyTargetGUID.hasPrefix("PACKAGE-TARGET:")
                else {
                    return nil
                }

                let dependencyTargetID = dependencyID.uri.stringValue
                let dependencyName =
                    cachedBuildTargetsByIDSnapshotValue(for: dependencyTargetID)?.displayName ?? "<nil>"
                let dependencySourcePaths = cachedSourceFilePathsByTargetIDSnapshot[dependencyTargetID] ?? []

                guard let packageRootURL = localPackageRootURL(fromSourceFilePaths: dependencySourcePaths) else {
                    return "\(dependencyName)<\(dependencyTargetGUID)> root=<unsupported>"
                }

                let packageFrameworksPath = packageRootURL
                    .appending(component: "build")
                    .appending(component: configurationName)
                    .appending(component: "PackageFrameworks")
                    .path()
                let packageBuildConfigurationPath = packageRootURL
                    .appending(component: "build")
                    .appending(component: configurationName)
                    .path()

                let frameworkExists = FileManager.default.fileExists(atPath: packageFrameworksPath)
                let includeExists = FileManager.default.fileExists(atPath: packageBuildConfigurationPath)

                let frameworkStatus =
                    frameworkPaths.contains(packageFrameworksPath) ? "present"
                    : (frameworkExists ? "missing" : "n/a")
                let includeStatus =
                    includePaths.contains(packageBuildConfigurationPath) ? "present"
                    : (includeExists ? "missing" : "n/a")

                return """
                    \(dependencyName)<\(dependencyTargetGUID)> \
                    root=\(packageRootURL.path()) \
                    framework=\(frameworkStatus) include=\(includeStatus)
                    """
            }

            guard dependencyCoverage.isEmpty == false else {
                return
            }

            logger.debug(
                """
                swift-build sourceKitOptions package dependency coverage \
                (id: \(String(describing: requestID)), sourceTarget: \(sourceTarget.displayName ?? "<nil>")<\(targetGUID(from: sourceTarget.id) ?? "<unknown>")>, \
                deps: \(dependencyCoverage.sorted()))
                """
            )
        }

        private func compilerArgumentsSummary(_ args: [String]) -> String {
            var includePaths: [String] = []
            var frameworkPaths: [String] = []
            var isystemPaths: [String] = []
            var moduleMapFiles: [String] = []

            var index = 0
            while index < args.count {
                let arg = args[index]

                if arg == "-Xcc", index + 1 < args.count {
                    let consumed = consumeSearchPathArguments(
                        args,
                        startIndex: index + 1,
                        isXccWrapped: true,
                        includePaths: &includePaths,
                        frameworkPaths: &frameworkPaths,
                        isystemPaths: &isystemPaths,
                        moduleMapFiles: &moduleMapFiles
                    )
                    if consumed > 0 {
                        index += 1 + consumed
                        continue
                    }
                }

                let consumed = consumeSearchPathArguments(
                    args,
                    startIndex: index,
                    isXccWrapped: false,
                    includePaths: &includePaths,
                    frameworkPaths: &frameworkPaths,
                    isystemPaths: &isystemPaths,
                    moduleMapFiles: &moduleMapFiles
                )
                if consumed > 0 {
                    index += consumed
                } else {
                    index += 1
                }
            }

            let preview = args.prefix(8).joined(separator: " ")
            return """
                includes=\(includePaths.count), frameworks=\(frameworkPaths.count), \
                isystem=\(isystemPaths.count), modulemaps=\(moduleMapFiles.count), \
                firstArgs=\"\(preview)\"
                """
        }

        private func resolvedCompilerPathsSummary(_ args: [String]) -> String {
            var includePaths: [String] = []
            var frameworkPaths: [String] = []
            var isystemPaths: [String] = []
            var moduleMapFiles: [String] = []

            var index = 0
            while index < args.count {
                let arg = args[index]

                if arg == "-Xcc", index + 1 < args.count {
                    let consumed = consumeSearchPathArguments(
                        args,
                        startIndex: index + 1,
                        isXccWrapped: true,
                        includePaths: &includePaths,
                        frameworkPaths: &frameworkPaths,
                        isystemPaths: &isystemPaths,
                        moduleMapFiles: &moduleMapFiles
                    )
                    if consumed > 0 {
                        index += 1 + consumed
                        continue
                    }
                }

                let consumed = consumeSearchPathArguments(
                    args,
                    startIndex: index,
                    isXccWrapped: false,
                    includePaths: &includePaths,
                    frameworkPaths: &frameworkPaths,
                    isystemPaths: &isystemPaths,
                    moduleMapFiles: &moduleMapFiles
                )
                if consumed > 0 {
                    index += consumed
                } else {
                    index += 1
                }
            }

            func uniquePreservingOrder(_ values: [String]) -> [String] {
                var seen = Set<String>()
                var result: [String] = []
                result.reserveCapacity(values.count)
                for value in values where seen.insert(value).inserted {
                    result.append(value)
                }
                return result
            }

            func compactList(_ values: [String], limit: Int = 8) -> String {
                let deduped = uniquePreservingOrder(values)
                let preview = deduped.prefix(limit)
                let suffix = deduped.count > limit ? ", ...(+\(deduped.count - limit) more)" : ""
                return "[\(preview.joined(separator: ", "))\(suffix)]"
            }

            let packageFrameworkPaths = frameworkPaths.filter {
                $0.localizedCaseInsensitiveContains("PackageFrameworks")
            }
            let sourcePackageModuleMaps = moduleMapFiles.filter {
                $0.localizedCaseInsensitiveContains("SourcePackages")
            }

            return """
                includes=\(compactList(includePaths)), \
                frameworks=\(compactList(frameworkPaths)), \
                isystem=\(compactList(isystemPaths)), \
                modulemaps=\(compactList(moduleMapFiles)), \
                packageFrameworks=\(compactList(packageFrameworkPaths)), \
                sourcePackageModuleMaps=\(compactList(sourcePackageModuleMaps))
                """
        }

        private func consumeSearchPathArguments(
            _ args: [String],
            startIndex: Int,
            isXccWrapped: Bool,
            includePaths: inout [String],
            frameworkPaths: inout [String],
            isystemPaths: inout [String],
            moduleMapFiles: inout [String]
        ) -> Int {
            guard startIndex < args.count else {
                return 0
            }

            let arg = args[startIndex]
            let nextValue: (Int) -> String? = { offset in
                let nextIndex = startIndex + offset
                guard nextIndex < args.count else {
                    return nil
                }
                if isXccWrapped {
                    guard args[nextIndex] == "-Xcc", nextIndex + 1 < args.count else {
                        return nil
                    }
                    return args[nextIndex + 1]
                }
                return args[nextIndex]
            }

            let consumeCountForValue = { (valueOffset: Int) -> Int in
                if isXccWrapped {
                    return valueOffset + 2
                }
                return valueOffset + 1
            }

            switch arg {
            case "-I":
                if let value = nextValue(1) {
                    includePaths.append(value)
                    return consumeCountForValue(1)
                }
            case "-F":
                if let value = nextValue(1) {
                    frameworkPaths.append(value)
                    return consumeCountForValue(1)
                }
            case "-isystem":
                if let value = nextValue(1) {
                    isystemPaths.append(value)
                    return consumeCountForValue(1)
                }
            case "-fmodule-map-file":
                if let value = nextValue(1) {
                    moduleMapFiles.append(value)
                    return consumeCountForValue(1)
                }
            default:
                if arg.hasPrefix("-I"), arg.count > 2 {
                    includePaths.append(String(arg.dropFirst(2)))
                    return 1
                }
                if arg.hasPrefix("-F"), arg.count > 2 {
                    frameworkPaths.append(String(arg.dropFirst(2)))
                    return 1
                }
                if arg.hasPrefix("-fmodule-map-file=") {
                    moduleMapFiles.append(String(arg.dropFirst("-fmodule-map-file=".count)))
                    return 1
                }
            }

            return 0
        }
    }

    fileprivate enum StartupError: LocalizedError {
        case missingWorkspaceContainerPath
        case workspaceContainerDoesNotExist(String)
        case invalidWorkspaceContainer(String)
        case pifDumpLaunchFailed(any Error)
        case pifDumpFailed(exitCode: Int32, stderr: String)
        case pifDumpOutputMissing(String)
        case pifDumpParseFailed(any Error)

        var errorDescription: String? {
            switch self {
            case .missingWorkspaceContainerPath:
                return """
                    Config missing `workspaceContainerPath` for SwiftBuild backend. \
                    Re-run `xcode-bsp config` in the project root.
                    """
            case .workspaceContainerDoesNotExist(let path):
                return "Configured workspace container does not exist: \(path)"
            case .invalidWorkspaceContainer(let path):
                return
                    "Configured workspace container must be a .xcodeproj or .xcworkspace: \(path)"
            case .pifDumpLaunchFailed(let error):
                return "Failed to launch `xcrun xcodebuild -dumpPIF`: \(error)"
            case .pifDumpFailed(let exitCode, let stderr):
                return "xcodebuild -dumpPIF failed with code \(exitCode): \(stderr)"
            case .pifDumpOutputMissing(let path):
                return "xcodebuild -dumpPIF did not produce output file at: \(path)"
            case .pifDumpParseFailed(let error):
                return "Failed to parse dumped PIF JSON: \(error)"
            }
        }
    }
}
