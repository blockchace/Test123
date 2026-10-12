import AVFoundation

enum AudioSpectrum {
    static func analyze(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let count = min(Int(buffer.frameLength), 1024)
        let channels = Int(buffer.format.channelCount)
        guard count > 0, channels > 0 else { return Array(repeating: 0, count: Spectrum.bands) }
        var mono = Array(repeating: Float(0), count: 1024)
        var strongestEnergy: Float = -1
        // Use the strongest channel: opposite stereo phases must not cancel the display.
        for channel in 0..<channels {
            var samples = Array(repeating: Float(0), count: 1024)
            var energy: Float = 0
            for frame in 0..<count {
                let plane = buffer.format.isInterleaved ? 0 : channel
                let index = buffer.format.isInterleaved ? frame * channels + channel : frame
                switch buffer.format.commonFormat {
                case .pcmFormatFloat32: samples[frame] = buffer.floatChannelData?[plane][index] ?? 0
                case .pcmFormatFloat64:
                    let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                    if let data = buffers[plane].mData { samples[frame] = Float(data.assumingMemoryBound(to: Double.self)[index]) }
                case .pcmFormatInt16: samples[frame] = Float(buffer.int16ChannelData?[plane][index] ?? 0) / 32768
                case .pcmFormatInt32: samples[frame] = Float(buffer.int32ChannelData?[plane][index] ?? 0) / 2147483648
                default: break
                }
                energy += samples[frame] * samples[frame]
            }
            if energy > strongestEnergy { strongestEnergy = energy; mono = samples }
        }
        return Spectrum.analyze(mono, sampleRate: buffer.format.sampleRate)
    }
}
