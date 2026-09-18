import XCTest
@testable import Strand

final class SleepStageBreakdownTests: XCTestCase {

    func testDecodesImportedMinutesDict() {
        let json = "{\"light\":210,\"deep\":80,\"rem\":95,\"awake\":25}"
        let s = SleepStageBreakdown.decode(json)
        XCTAssertEqual(s?.light, 210)
        XCTAssertEqual(s?.deep, 80)
        XCTAssertEqual(s?.rem, 95)
        XCTAssertEqual(s?.awake, 25)
        XCTAssertEqual(s?.total, 410)
        XCTAssertEqual(s?.asleep, 385)
    }

    /// The regression that made Sleep look empty after overnight wear: on-device
    /// scoring writes hypnogram segments, and only the minutes dict was handled.
    func testDecodesComputedSegmentArray() {
        let json = """
        [{"start":0,"end":1800,"stage":"light"},
         {"start":1800,"end":5400,"stage":"deep"},
         {"start":5400,"end":9000,"stage":"rem"},
         {"start":9000,"end":9600,"stage":"wake"}]
        """
        let s = SleepStageBreakdown.decode(json)
        XCTAssertEqual(s?.light, 30)
        XCTAssertEqual(s?.deep, 60)
        XCTAssertEqual(s?.rem, 60)
        XCTAssertEqual(s?.awake, 10)
        XCTAssertEqual(s?.total, 160)
    }

    func testSegmentsAccumulateRepeatedStages() {
        let json = """
        [{"start":0,"end":600,"stage":"light"},
         {"start":600,"end":1200,"stage":"deep"},
         {"start":1200,"end":1800,"stage":"light"}]
        """
        XCTAssertEqual(SleepStageBreakdown.decode(json)?.light, 20)
    }

    func testUnknownStageCountsAsLight() {
        let json = "[{\"start\":0,\"end\":600,\"stage\":\"unclassified\"}]"
        XCTAssertEqual(SleepStageBreakdown.decode(json)?.light, 10)
    }

    func testRejectsEmptyMalformedAndZeroTotals() {
        XCTAssertNil(SleepStageBreakdown.decode(nil))
        XCTAssertNil(SleepStageBreakdown.decode(""))
        XCTAssertNil(SleepStageBreakdown.decode("not json"))
        XCTAssertNil(SleepStageBreakdown.decode("{\"light\":0,\"deep\":0,\"rem\":0,\"awake\":0}"))
        XCTAssertNil(SleepStageBreakdown.decode("[]"))
        // A segment that ends before it starts is dropped, not negated.
        XCTAssertNil(SleepStageBreakdown.decode("[{\"start\":600,\"end\":0,\"stage\":\"deep\"}]"))
    }
}
