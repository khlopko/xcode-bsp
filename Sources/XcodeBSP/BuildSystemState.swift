import Foundation

struct PendingBuildSystemChanges: Sendable {
    let changedTargetURIs: [String]
    let changedOptionsByFilePath: [String: CompilerOptions]
}

actor BuildSystemState {
    private var registeredURIs: Set<String>
    private var anonymousRegistrationCount: Int

    private var pendingUpdatesCount: Int
    private var waiters: [CheckedContinuation<Void, Never>]

    private var pendingChangedTargetURIs: Set<String>
    private var pendingChangedOptionsByFilePath: [String: CompilerOptions]

    private var didReceiveShutdown: Bool

    init() {
        registeredURIs = []
        anonymousRegistrationCount = 0
        pendingUpdatesCount = 0
        waiters = []
        pendingChangedTargetURIs = []
        pendingChangedOptionsByFilePath = [:]
        didReceiveShutdown = false
    }

    func updateRegistration(action: String?, uri: String?) {
        if action?.lowercased() == "unregister" {
            if let uri, uri.isEmpty == false {
                registeredURIs.remove(uri)
            } else {
                anonymousRegistrationCount = max(0, anonymousRegistrationCount - 1)
            }
            return
        }

        if let uri, uri.isEmpty == false {
            registeredURIs.insert(uri)
        } else {
            anonymousRegistrationCount += 1
        }
    }

    func registeredDocumentURIs() -> [String] {
        return Array(registeredURIs).sorted()
    }

    func hasRegisteredDocuments() -> Bool {
        return anonymousRegistrationCount > 0 || registeredURIs.isEmpty == false
    }

    func beginUpdate() {
        pendingUpdatesCount += 1
    }

    func endUpdate() {
        if pendingUpdatesCount > 0 {
            pendingUpdatesCount -= 1
        }

        if pendingUpdatesCount == 0 {
            let continuations = waiters
            waiters = []
            for continuation in continuations {
                continuation.resume()
            }
        }
    }

    func waitForIdle() async {
        guard pendingUpdatesCount > 0 else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func recordRefreshChanges(_ refresh: BuildGraphRefreshResult) {
        for targetURI in refresh.changedTargetURIs {
            pendingChangedTargetURIs.insert(targetURI)
        }

        for (filePath, options) in refresh.changedOptionsByFilePath {
            pendingChangedOptionsByFilePath[filePath] = options
        }
    }

    func drainPendingChanges() -> PendingBuildSystemChanges {
        let result = PendingBuildSystemChanges(
            changedTargetURIs: Array(pendingChangedTargetURIs).sorted(),
            changedOptionsByFilePath: pendingChangedOptionsByFilePath
        )
        pendingChangedTargetURIs = []
        pendingChangedOptionsByFilePath = [:]
        return result
    }

    func markShutdownReceived() {
        didReceiveShutdown = true
    }

    func hasReceivedShutdown() -> Bool {
        return didReceiveShutdown
    }
}
