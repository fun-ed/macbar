import XCTest
import CoreAudio
import AppAudioRT

final class AppAudioRTTests: XCTestCase {
    func testInterleavedAttenuationMuteAndGainClamp() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 2, 0, 0))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetEnabled(rt, 1)
        MBAppAudioRTSetGain(rt, 0.5)
        XCTAssertEqual(render(rt, input: [1, -1, 0.4, -0.4]), [0.5, -0.5, 0.2, -0.2])
        MBAppAudioRTSetGain(rt, 0)
        XCTAssertEqual(render(rt, input: [1, -1]), [0, 0])
        XCTAssertEqual(MBAppAudioRTSignals(rt), 2) // Mute still verifies pre-gain captured audio.
        MBAppAudioRTSetGain(rt, 4)
        XCTAssertEqual(render(rt, input: [1, -1]), [1, -1])
        MBAppAudioRTSetGain(rt, .nan)
        XCTAssertEqual(render(rt, input: [1, -1]), [0, 0])
        MBAppAudioRTSetEnabled(rt, 0)
        XCTAssertEqual(render(rt, input: [1, -1]), [0, 0])
        XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
    }

    func testSilentInputDoesNotVerifyPermission() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 2, 0, 0))
        defer { MBAppAudioRTDestroy(rt) }
        XCTAssertEqual(render(rt, input: [0, 0]), [0, 0])
        XCTAssertEqual(MBAppAudioRTCallbacks(rt), 1)
        XCTAssertEqual(MBAppAudioRTSignals(rt), 0)
    }

    func testMonoOutputAveragesStereo() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 1, 0, 0))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetEnabled(rt, 1)
        MBAppAudioRTSetGain(rt, 0.5)
        XCTAssertEqual(render(rt, input: [1, 0.5, -1, -0.5], channels: 1), [0.375, -0.375])
    }

    func testSixChannelOutputGainMuteAndUnusedChannelsCleared() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 6, 0, 0))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetEnabled(rt, 1)
        MBAppAudioRTSetGain(rt, 0.5)
        let samples: [Float] = [1, -1, 0.5, -0.5]
        XCTAssertEqual(render(rt, input: samples, channels: 6, initialOutput: 99),
                       [0.5, -0.5, 0, 0, 0, 0, 0.25, -0.25, 0, 0, 0, 0])
        MBAppAudioRTSetGain(rt, 0)
        XCTAssertEqual(render(rt, input: samples, channels: 6, initialOutput: 99), [Float](repeating: 0, count: 12))
        MBAppAudioRTSetGain(rt, 1)
        XCTAssertEqual(render(rt, input: [1, -1], channels: 6, initialOutput: 99), [1, -1, 0, 0, 0, 0])
        XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
    }

    func testNonDefaultStereoChannelsAndReversedStereo() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayoutWithStereoChannels(0, 1, 6, 0, 0, 2, 5))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetEnabled(rt, 1)
        MBAppAudioRTSetGain(rt, 0.5)
        XCTAssertEqual(render(rt, input: [1, -1, 0.5, -0.5], channels: 6, initialOutput: 99),
                       [0, 0, 0.5, 0, 0, -0.5, 0, 0, 0.25, 0, 0, -0.25])
        XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
        let reversed = try XCTUnwrap(MBAppAudioRTCreateLayoutWithStereoChannels(0, 1, 2, 0, 0, 1, 0))
        defer { MBAppAudioRTDestroy(reversed) }
        MBAppAudioRTSetEnabled(reversed, 1)
        MBAppAudioRTSetGain(reversed, 1)
        XCTAssertEqual(render(reversed, input: [1, -1]), [-1, 1])
    }

    func testPlanarMultichannelOutputMapsOnlyPreferredStereoChannels() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayoutWithStereoChannels(0, 2, 6, 1, 1, 4, 1))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetEnabled(rt, 1)
        MBAppAudioRTSetGain(rt, 0.5)
        XCTAssertEqual(renderPlanar(rt, left: [1, 0.5], right: [-1, -0.5], channels: 6),
                       [0, 0, -0.5, -0.25, 0, 0, 0, 0, 0.5, 0.25, 0, 0])
        MBAppAudioRTSetGain(rt, 0)
        XCTAssertEqual(renderPlanar(rt, left: [1, 0.5], right: [-1, -0.5], channels: 6), [Float](repeating: 0, count: 12))
        XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
    }

    func testMaximumChannelLayoutsAndMultichannelFaultClear() throws {
        for planar in [false, true] {
            let rt = try XCTUnwrap(MBAppAudioRTCreateLayoutWithStereoChannels(0, planar ? 2 : 1, 32,
                                                                           planar ? 1 : 0, planar ? 1 : 0, 31, 0))
            defer { MBAppAudioRTDestroy(rt) }
            MBAppAudioRTSetEnabled(rt, 1)
            MBAppAudioRTSetGain(rt, 1)
            var expected = [Float](repeating: 0, count: 32)
            expected[0] = -1
            expected[31] = 1
            let actual = planar ? renderPlanar(rt, left: [1], right: [-1], channels: 32) :
                render(rt, input: [1, -1], channels: 32, initialOutput: 99)
            XCTAssertEqual(actual, expected)
            XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
        }
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 6, 0, 0))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetEnabled(rt, 1)
        MBAppAudioRTSetGain(rt, 1)
        var samples = [Float](repeating: 1, count: 8192 * 2)
        samples[samples.count - 1] = .nan
        // Larger than the old stereo byte bound, with partial writes before the fault.
        XCTAssertEqual(render(rt, input: samples, channels: 6, initialOutput: 99), [Float](repeating: 0, count: 8192 * 6))
        XCTAssertEqual(MBAppAudioRTFaulted(rt), 1)
    }

    func testNonFiniteSamplesAndMismatchedFrameCountFailSilent() throws {
        let cases: [[Float]] = [[1, 1, .nan, 1], [1, 1, .infinity, 1]]
        for samples in cases {
            let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 2, 0, 0))
            defer { MBAppAudioRTDestroy(rt) }
            MBAppAudioRTSetEnabled(rt, 1)
            MBAppAudioRTSetGain(rt, 0.5)
            XCTAssertEqual(render(rt, input: samples), [0, 0, 0, 0])
            XCTAssertEqual(MBAppAudioRTFaulted(rt), 1)
        }
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(0, 1, 2, 0, 0))
        defer { MBAppAudioRTDestroy(rt) }
        XCTAssertEqual(render(rt, input: [1, 1], outputSamples: 4), [0, 0, 0, 0])
        XCTAssertEqual(MBAppAudioRTFaulted(rt), 1)
    }

    func testPlanarInputAndOutputWithDisabledPhysicalInputPrefix() throws {
        let rt = try XCTUnwrap(MBAppAudioRTCreateLayout(1, 2, 2, 1, 1))
        defer { MBAppAudioRTDestroy(rt) }
        MBAppAudioRTSetGain(rt, 0.5)
        MBAppAudioRTSetEnabled(rt, 1)
        let left: [Float] = [1, 0.5]
        let right: [Float] = [-1, -0.5]
        var resultLeft: [Float] = [0, 0]
        var resultRight: [Float] = [0, 0]
        let input = makeList(3), output = makeList(2)
        defer {
            UnsafeMutableRawPointer(input.unsafeMutablePointer).deallocate()
            UnsafeMutableRawPointer(output.unsafeMutablePointer).deallocate()
        }
        left.withUnsafeBytes { l in
            right.withUnsafeBytes { r in
                resultLeft.withUnsafeMutableBytes { ol in
                    resultRight.withUnsafeMutableBytes { or in
                        input[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: nil)
                        input[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: UnsafeMutableRawPointer(mutating: l.baseAddress))
                        input[2] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: UnsafeMutableRawPointer(mutating: r.baseAddress))
                        output[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: ol.baseAddress)
                        output[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: or.baseAddress)
                        invoke(rt, input.unsafePointer, output.unsafeMutablePointer)
                        XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
                        XCTAssertEqual(Array(ol.bindMemory(to: Float.self)), [0.5, 0.25])
                        XCTAssertEqual(Array(or.bindMemory(to: Float.self)), [-0.5, -0.25])
                        let physical: [Float] = [17, .nan]
                        physical.withUnsafeBytes { prefix in
                            input[0].mData = UnsafeMutableRawPointer(mutating: prefix.baseAddress)
                            invoke(rt, input.unsafePointer, output.unsafeMutablePointer)
                            XCTAssertEqual(MBAppAudioRTFaulted(rt), 0)
                            XCTAssertEqual(Array(ol.bindMemory(to: Float.self)), [0.5, 0.25])
                            XCTAssertEqual(Array(or.bindMemory(to: Float.self)), [-0.5, -0.25])
                        }
                    }
                }
            }
        }
        XCTAssertEqual(resultLeft, [0.5, 0.25])
        XCTAssertEqual(resultRight, [-0.5, -0.25])
    }

    func testInvalidLayoutsAreRejected() {
        XCTAssertNil(MBAppAudioRTCreateLayout(32, 1, 2, 0, 0))
        XCTAssertNil(MBAppAudioRTCreateLayout(0, 1, 0, 0, 0))
        XCTAssertNil(MBAppAudioRTCreateLayout(0, 1, 33, 0, 0))
        XCTAssertNil(MBAppAudioRTCreateLayout(0, 1, 2, 1, 0))
    }

    func testInvalidStereoChannelMappingsAreRejected() {
        XCTAssertNil(MBAppAudioRTCreateLayoutWithStereoChannels(0, 1, 6, 0, 0, 2, 2))
        XCTAssertNil(MBAppAudioRTCreateLayoutWithStereoChannels(0, 1, 6, 0, 0, 6, 1))
        XCTAssertNil(MBAppAudioRTCreateLayoutWithStereoChannels(0, 2, 6, 1, 1, 0, 6))
        XCTAssertNil(MBAppAudioRTCreateLayoutWithStereoChannels(0, 1, 6, 0, 0, UInt32.max, 1))
        XCTAssertNil(MBAppAudioRTCreateLayoutWithStereoChannels(0, 1, 1, 0, 0, 0, 1))
    }

    private func render(_ rt: OpaquePointer, input samples: [Float], channels: UInt32 = 2,
                        outputSamples: Int? = nil, initialOutput: Float = 0) -> [Float] {
        var destination = [Float](repeating: initialOutput, count: outputSamples ?? samples.count / 2 * Int(channels))
        samples.withUnsafeBytes { source in
            destination.withUnsafeMutableBytes { target in
                var input = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2,
                    mDataByteSize: UInt32(source.count), mData: UnsafeMutableRawPointer(mutating: source.baseAddress)))
                var output = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: channels,
                    mDataByteSize: UInt32(target.count), mData: target.baseAddress))
                withUnsafePointer(to: &input) { inputPointer in
                    withUnsafeMutablePointer(to: &output) { invoke(rt, inputPointer, $0) }
                }
            }
        }
        return destination
    }

    private func renderPlanar(_ rt: OpaquePointer, left: [Float], right: [Float], channels: Int) -> [Float] {
        let input = makeList(2), output = makeList(channels)
        defer {
            UnsafeMutableRawPointer(input.unsafeMutablePointer).deallocate()
            UnsafeMutableRawPointer(output.unsafeMutablePointer).deallocate()
        }
        var destination = [Float](repeating: 99, count: left.count * channels)
        left.withUnsafeBytes { l in
            right.withUnsafeBytes { r in
                destination.withUnsafeMutableBytes { target in
                    input[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(l.count),
                                           mData: UnsafeMutableRawPointer(mutating: l.baseAddress))
                    input[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(r.count),
                                           mData: UnsafeMutableRawPointer(mutating: r.baseAddress))
                    let bytesPerChannel = l.count
                    for channel in 0..<channels {
                        output[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytesPerChannel),
                                                      mData: target.baseAddress!.advanced(by: channel * bytesPerChannel))
                    }
                    invoke(rt, input.unsafePointer, output.unsafeMutablePointer)
                }
            }
        }
        return destination
    }

    private func invoke(_ rt: OpaquePointer, _ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        var timestamp = AudioTimeStamp()
        withUnsafePointer(to: &timestamp) { time in
            XCTAssertEqual(MBAppAudioRTIOProc(0, time, input, time, output, time, UnsafeMutableRawPointer(rt)), noErr)
        }
    }

    private func makeList(_ count: Int) -> UnsafeMutableAudioBufferListPointer {
        AudioBufferList.allocate(maximumBuffers: count)
    }
}
