import XCTest
@testable import ParaDict

final class ApplicationInstanceServiceTests: XCTestCase {
    func testReturnsOtherProcessIdentifierWhenAnotherInstanceIsRunning() {
        let result = ApplicationInstanceService.otherProcessIdentifier(
            currentProcessIdentifier: 42,
            runningProcessIdentifiers: [42, 84]
        )

        XCTAssertEqual(result, 84)
    }

    func testReturnsNilWhenOnlyCurrentInstanceIsRunning() {
        let result = ApplicationInstanceService.otherProcessIdentifier(
            currentProcessIdentifier: 42,
            runningProcessIdentifiers: [42]
        )

        XCTAssertNil(result)
    }
}
