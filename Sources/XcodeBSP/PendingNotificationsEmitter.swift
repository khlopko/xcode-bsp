import Foundation

final class PendingNotificationsEmitter: Sendable {
    private let conn: JSONRPCConnection
    private let state: BuildSystemState
    private let enableLegacySourceKitOptionsChanged: Bool

    init(
        conn: JSONRPCConnection,
        state: BuildSystemState,
        enableLegacySourceKitOptionsChanged: Bool
    ) {
        self.conn = conn
        self.state = state
        self.enableLegacySourceKitOptionsChanged = enableLegacySourceKitOptionsChanged
    }

    func emit() async throws {
        let pending = await state.drainPendingChanges()

        if pending.changedTargetURIs.isEmpty == false {
            let changes = pending.changedTargetURIs.map {
                BuildTargetDidChange(target: TargetID(uri: $0), kind: .changed)
            }
            try conn.send(
                message: JSONRPCNotificationMessage(
                    method: "buildTarget/didChange",
                    params: BuildTargetDidChangeParams(changes: changes)
                )
            )
        }

        guard enableLegacySourceKitOptionsChanged else {
            return
        }

        guard await state.hasRegisteredDocuments() else {
            return
        }

        let registeredURIs = await state.registeredDocumentURIs()
        for uri in registeredURIs {
            guard let filePath = filePath(fromDocumentURI: uri) else {
                continue
            }

            let resolved = URL(filePath: filePath).resolvingSymlinksInPath().path()
            guard
                let options = pending.changedOptionsByFilePath[filePath]
                    ?? pending.changedOptionsByFilePath[resolved]
            else {
                continue
            }

            try conn.send(
                message: JSONRPCNotificationMessage(
                    method: "build/sourceKitOptionsChanged",
                    params: BuildSourceKitOptionsChangedParams(
                        uri: uri,
                        updatedOptions: BuildSourceKitOptionsChangedParams.UpdatedOptions(
                            options: options.options,
                            workingDirectory: options.workingDirectory
                        )
                    )
                )
            )
        }
    }

    private func filePath(fromDocumentURI documentURI: String) -> String? {
        guard let url = URL(string: documentURI), url.isFileURL else {
            return nil
        }

        return URL(filePath: url.path()).standardizedFileURL.path()
    }
}
