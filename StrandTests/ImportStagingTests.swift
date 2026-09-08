import XCTest
@testable import Strand

final class ImportStagingTests: XCTestCase {
    func testCopyNowDuplicatesBytesToANewFile() throws {
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("noop-src-\(UUID().uuidString)")
            .appendingPathExtension("zip")
        let payload = Data("hello-whoop-export".utf8)
        try payload.write(to: src)
        defer { try? FileManager.default.removeItem(at: src) }

        let dest = try ImportStaging.copyNow(src)
        defer { try? FileManager.default.removeItem(at: dest) }

        XCTAssertNotEqual(dest.path, src.path)
        XCTAssertEqual(try Data(contentsOf: dest), payload)
        XCTAssertEqual(dest.pathExtension, "zip")
    }

    func testCopyNowFailsOnMissingFile() {
        let missing = URL(fileURLWithPath: "/tmp/noop-does-not-exist-\(UUID().uuidString).zip")
        XCTAssertThrowsError(try ImportStaging.copyNow(missing))
    }
}
