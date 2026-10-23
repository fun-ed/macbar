import XCTest
@testable import macbar

final class LevelMeterTests: XCTestCase {
    func testPublicationIsLimitedTo2HzAndRepeatedPositiveValuesRemainEligible() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 1, now: 1) { delivered.append($0) }
        meter.push(rawLevel: 1, now: 1.49) { delivered.append($0) }
        XCTAssertEqual(delivered, [1])

        meter.push(rawLevel: 1, now: 1.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [1, 1])

        meter.push(rawLevel: 1, now: 2) { delivered.append($0) }
        XCTAssertEqual(delivered, [1, 1, 1])
    }

    func testSustainedSilenceSuppressesPublicationsButPreservesTimeBookkeeping() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        for second in 1...10 {
            meter.push(rawLevel: 0, now: Double(second)) { delivered.append($0) }
        }
        XCTAssertEqual(delivered, [])

        meter.push(rawLevel: 0.5, now: 10.49) { delivered.append($0) }
        XCTAssertEqual(delivered, [])

        meter.push(rawLevel: 0.5, now: 10.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.5])
    }

    func testDecayDeliversSilenceExactlyOnceAndNewPositiveSignalIsDelivered() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 0.6, now: 1) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.6])

        meter.push(rawLevel: 0, now: 1.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.6, 0])

        meter.push(rawLevel: 0, now: 2) { delivered.append($0) }
        meter.push(rawLevel: 0, now: 2.5) { delivered.append($0) }
        meter.push(rawLevel: 0, now: 3) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.6, 0])

        meter.push(rawLevel: 0.6, now: 3.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.6, 0, 0.6])
    }

    func testResetClearsSmoothingAndThrottleAndPermitsNextAudiblePublication() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 1, now: 10) { delivered.append($0) }
        meter.reset()
        meter.push(rawLevel: 0.25, now: 10.01) { delivered.append($0) }
        XCTAssertEqual(delivered, [1, 0.25])

        meter.reset()
        meter.push(rawLevel: 0, now: 10.02) { delivered.append($0) }
        XCTAssertEqual(delivered, [1, 0.25])

        meter.push(rawLevel: 0.5, now: 10.53) { delivered.append($0) }
        XCTAssertEqual(delivered, [1, 0.25, 0.5])
    }

    func testBriefSignalInsideBlockedWindowIsDeliveredAtPublication() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 0, now: 1) { delivered.append($0) }
        meter.push(rawLevel: 0.8, now: 1.25) { delivered.append($0) }
        meter.push(rawLevel: 0.4, now: 1.49) { delivered.append($0) }
        XCTAssertEqual(delivered, [])

        meter.push(rawLevel: 0, now: 1.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.8])
    }

    func testConsumedPeakIsNotReusedInNextWindow() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 0, now: 1) { delivered.append($0) }
        meter.push(rawLevel: 0.8, now: 1.49) { delivered.append($0) }
        meter.push(rawLevel: 0, now: 1.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.8])

        meter.push(rawLevel: 0, now: 2) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.8, 0])
    }

    func testResetClearsPendingPeak() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 0, now: 1) { delivered.append($0) }
        meter.push(rawLevel: 0.9, now: 1.49) { delivered.append($0) }
        meter.reset()
        meter.push(rawLevel: 0, now: 1.5) { delivered.append($0) }
        XCTAssertEqual(delivered, [])

        meter.push(rawLevel: 0.25, now: 2) { delivered.append($0) }
        XCTAssertEqual(delivered, [0.25])
    }

    func testHighSignalDecaysBelowPoint02InFirstSilentWindowAndReachesZeroInSecond() {
        let meter = LevelMeter()
        var delivered: [Double] = []

        meter.push(rawLevel: 1, now: 1) { delivered.append($0) }
        meter.push(rawLevel: 0, now: 1.5) { delivered.append($0) }
        XCTAssertEqual(delivered.count, 2)
        guard delivered.count == 2 else { return }
        XCTAssertEqual(delivered[0], 1)
        XCTAssertGreaterThan(delivered[1], 0)
        XCTAssertLessThan(delivered[1], 0.02)

        meter.push(rawLevel: 0, now: 2) { delivered.append($0) }
        XCTAssertEqual(delivered.count, 3)
        XCTAssertEqual(delivered.last, 0)
    }
}
