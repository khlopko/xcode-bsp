import Foundation
import Logging

protocol RefreshTrigger: Sendable {
    func requestRefresh(reason: String) async
}

actor BackgroundRefreshCoordinator: RefreshTrigger {
    typealias RefreshAction = @Sendable (_ reason: String) async -> Void

    private let logger: Logger
    private let refreshAction: RefreshAction

    private var isRefreshing: Bool

    init(logger: Logger, refreshAction: @escaping RefreshAction) {
        self.logger = logger
        self.refreshAction = refreshAction
        isRefreshing = false
    }

    func requestRefresh(reason: String) async {
        guard isRefreshing == false else {
            logger.trace("background refresh request coalesced; already in flight (reason=\(reason))")
            return
        }

        isRefreshing = true
        logger.trace("background refresh scheduled (reason=\(reason))")

        Task { [refreshAction, logger] in
            logger.trace("background refresh started (reason=\(reason))")
            await refreshAction(reason)
            logger.trace("background refresh finished (reason=\(reason))")
            self.markRefreshFinished()
        }
    }

    private func markRefreshFinished() {
        isRefreshing = false
    }
}
