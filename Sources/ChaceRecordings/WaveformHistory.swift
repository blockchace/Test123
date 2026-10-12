import Foundation
import Combine

final class AudioMonitor: ObservableObject {
    @Published private(set) var system = Array(repeating: Float(0), count: WaveformHistory.capacity)
    @Published private(set) var microphone = Array(repeating: Float(0), count: WaveformHistory.capacity)
    @Published private(set) var systemReceiving = false
    @Published private(set) var microphoneReceiving = false

    func update(system: [Float], microphone: [Float], systemReceiving: Bool, microphoneReceiving: Bool) {
        if self.system != system { self.system = system }
        if self.microphone != microphone { self.microphone = microphone }
        if self.systemReceiving != systemReceiving { self.systemReceiving = systemReceiving }
        if self.microphoneReceiving != microphoneReceiving { self.microphoneReceiving = microphoneReceiving }
    }

    func clear() {
        let empty = Array(repeating: Float(0), count: WaveformHistory.capacity)
        update(system: empty, microphone: empty, systemReceiving: false, microphoneReceiving: false)
    }
}

struct WaveformHistory {
    static let capacity = 64
    private(set) var values = Array(repeating: Float(0), count: capacity)

    mutating func append(peak: Float) {
        let finite = peak.isFinite ? max(0, min(1, peak)) : 0
        // Display gain only; the recorded audio is never amplified here.
        let visible = finite < 0.0001 ? 0 : min(1, sqrt(finite) * 1.4)
        values.removeFirst()
        values.append(visible)
    }

    mutating func clear() { values = Array(repeating: 0, count: Self.capacity) }
}
