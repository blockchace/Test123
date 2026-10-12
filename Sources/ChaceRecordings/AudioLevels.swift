import AVFoundation

enum AudioLevels {
    static func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        var peak: Float = 0
        for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            guard let data = audio.mData else { continue }
            switch buffer.format.commonFormat {
            case .pcmFormatFloat32:
                let values = data.assumingMemoryBound(to: Float.self)
                for i in 0..<(Int(audio.mDataByteSize) / 4) { peak = max(peak, abs(values[i])) }
            case .pcmFormatFloat64:
                let values = data.assumingMemoryBound(to: Double.self)
                for i in 0..<(Int(audio.mDataByteSize) / 8) { peak = max(peak, Float(abs(values[i]))) }
            case .pcmFormatInt16:
                let values = data.assumingMemoryBound(to: Int16.self)
                for i in 0..<(Int(audio.mDataByteSize) / 2) { peak = max(peak, abs(Float(values[i])) / 32768) }
            case .pcmFormatInt32:
                let values = data.assumingMemoryBound(to: Int32.self)
                for i in 0..<(Int(audio.mDataByteSize) / 4) { peak = max(peak, abs(Float(values[i])) / 2147483648) }
            default: break
            }
        }
        return peak
    }

}
