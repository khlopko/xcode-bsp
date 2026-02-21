import XCTest
@testable import XcodeBSP

final class BackgroundRefreshCoordinatorTests: XCTestCase {
    func testCoalescesConcurrentRequestsIntoSingleRefresh() async {
        actor Counter {
            private(set) var count: Int = 0

            func increment() {
                count += 1
            }
        }

        let counter = Counter()
        let coordinator = BackgroundRefreshCoordinator(
            logger: makeTestLogger(),
            refreshAction: { _ in
                await counter.increment()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        )

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask {
                    await coordinator.requestRefresh(reason: "test-\(index)")
                }
            }
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
}
