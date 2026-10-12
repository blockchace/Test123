import XCTest
import AVFoundation
@testable import ChaceRecordings

final class AudioLevelsTests: XCTestCase {
    func testOppositeStereoPhasesDoNotCancelPeak() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<1024 { channels[0][index] = 0.5; channels[1][index] = -0.5 }
        XCTAssertEqual(AudioLevels.peak(buffer), 0.5, accuracy: 0.0001)
    }

    func testInterleavedRightChannelIsDetected() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        for index in 0..<480 { data[index * 2] = 0; data[index * 2 + 1] = 0.75 }
        XCTAssertEqual(AudioLevels.peak(buffer), 0.75, accuracy: 0.0001)
    }

    func testNegativeInt16FullScaleDoesNotOverflow() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        buffer.frameLength = 1
        let data = try XCTUnwrap(buffer.int16ChannelData)
        data[0][0] = Int16.min
        XCTAssertEqual(AudioLevels.peak(buffer), 1, accuracy: 0.0001)
    }
}
