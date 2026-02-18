import Foundation

actor BuildSystemState {
    private var registeredDocumentsCount: Int
    private var pendingUpdatesCount: Int
    private var waiters: [CheckedContinuation<Void, Never>]
    private var didReceiveShutdown: Bool

    init() {
        registeredDocumentsCount = 0
        pendingUpdatesCount = 0
        waiters = []
        didReceiveShutdown = false
    }

    func updateRegistration(action: String?) {
        if action?.lowercased() == "unregister" {
            registeredDocumentsCount = max(0, registeredDocumentsCount - 1)
            return
        }

        registeredDocumentsCount += 1
    }

    func hasRegisteredDocuments() -> Bool {
        return registeredDocumentsCount > 0
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

    func markShutdownReceived() {
        didReceiveShutdown = true
    }

    func hasReceivedShutdown() -> Bool {
        return didReceiveShutdown
    }
}
