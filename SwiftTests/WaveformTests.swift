import XCTest
@testable import ChaceRecordings

final class WaveformTests: XCTestCase {
    func testLongRecordingHistoryRemainsBounded() {
        var history = WaveformHistory()
        for _ in 0..<100_000 { history.append(peak: 0.5) }
        XCTAssertEqual(history.values.count, 64)
        XCTAssertTrue(history.values.allSatisfy { $0 > 0 && $0 <= 1 })
        for _ in 0..<64 { history.append(peak: 0) }
        XCTAssertEqual(history.values, Array(repeating: 0, count: 64))
    }

    func testNonFiniteValuesDoNotBreakDrawing() {
        var history = WaveformHistory()
        let values: [Float] = [.nan, .infinity, -.infinity, -1, 2]
        for value in values { history.append(peak: value) }
        XCTAssertTrue(history.values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        history.clear()
        XCTAssertEqual(history.values.count, 64)
        XCTAssertTrue(history.values.allSatisfy { $0 == 0 })
    }
}
