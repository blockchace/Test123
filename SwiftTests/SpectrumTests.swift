import XCTest
import AVFoundation
@testable import AireAudio

final class SpectrumTests: XCTestCase {
    func testSilenceIsFlat() {
        XCTAssertEqual(Spectrum.analyze(Array(repeating: 0, count: 1024), sampleRate: 48000), Array(repeating: 0, count: 24))
    }

    func testFrequencyPeakMovesBetweenLowAndHighTones() {
        func peak(_ frequency: Double) -> Int {
            let samples = (0..<1024).map { Float(0.5 * sin(2 * Double.pi * frequency * Double($0) / 48000)) }
            let values = Spectrum.analyze(samples, sampleRate: 48000)
            XCTAssertTrue(values.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
            return values.indices.max(by: { values[$0] < values[$1] })!
        }
        XCTAssertLessThan(peak(440), peak(4000))
    }

    func testVeryLowLevelIsLessVisibleThanLoudTone() {
        func strength(_ gain: Double) -> Float {
            let samples = (0..<1024).map { Float(gain * sin(2 * Double.pi * 1000 * Double($0) / 48000)) }
            return Spectrum.analyze(samples, sampleRate: 48000).max()!
        }
        XCTAssertLessThan(strength(0.001), strength(0.5))
    }

    func testStereoSignalDoesNotDisappearWithOppositePhases() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<1024 {
            let value = Float(0.5 * sin(2 * Double.pi * 1000 * Double(index) / 48000))
            channels[0][index] = value
            channels[1][index] = -value
        }
        XCTAssertGreaterThan(AudioSpectrum.analyze(buffer).max()!, 0.5)
    }

    func testShortInterleavedBuffersStillShowAudioInRightChannel() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<480 {
            data[index * 2] = 0
            data[index * 2 + 1] = Float(0.5 * sin(2 * Double.pi * 1000 * Double(index) / 48000))
        }
        XCTAssertGreaterThan(AudioSpectrum.analyze(buffer).max()!, 0.1)
    }
}
