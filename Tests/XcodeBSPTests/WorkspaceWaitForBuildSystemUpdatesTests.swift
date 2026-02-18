import Foundation
import XCTest
@testable import XcodeBSP

final class WorkspaceWaitForBuildSystemUpdatesTests: XCTestCase {
    func testWaitBlocksUntilPendingUpdatesFinish() async throws {
        let state = BuildSystemState()
        let handler = WorkspaceWaitForBuildSystemUpdates(state: state)
        let flag = CompletionFlag()

        await state.beginUpdate()
        let task = Task {
            _ = try await handler.handle(
                request: Request(id: "1", method: handler.method, params: WorkspaceWaitForBuildSystemUpdates.Params()),
                decoder: JSONDecoder()
            )
            await flag.markCompleted()
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        let isCompletedBeforeEnd = await flag.isCompleted()
        XCTAssertEqual(isCompletedBeforeEnd, false)

        await state.endUpdate()
        _ = try await task.value
        let isCompletedAfterEnd = await flag.isCompleted()
        XCTAssertEqual(isCompletedAfterEnd, true)
    }
}

private actor CompletionFlag {
    private var completed: Bool = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        return completed
    }
}
