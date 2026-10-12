import Foundation

enum Spectrum {
    static let bands = 24
    static func analyze(_ samples: [Float], sampleRate: Double) -> [Float] {
        let n = 1024
        guard samples.count >= n, sampleRate > 0 else { return Array(repeating: 0, count: bands) }
        var real = (0..<n).map { Double(samples[$0]) * (0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1))) }
        var imaginary = Array(repeating: Double(0), count: n)
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i < j { real.swapAt(i, j) }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let wr = cos(angle), wi = sin(angle)
            for start in stride(from: 0, to: n, by: length) {
                var ur = 1.0, ui = 0.0
                for offset in 0..<(length / 2) {
                    let a = start + offset, b = a + length / 2
                    let tr = real[b] * ur - imaginary[b] * ui
                    let ti = real[b] * ui + imaginary[b] * ur
                    real[b] = real[a] - tr; imaginary[b] = imaginary[a] - ti
                    real[a] += tr; imaginary[a] += ti
                    let next = ur * wr - ui * wi
                    ui = ur * wi + ui * wr; ur = next
                }
            }
            length *= 2
        }
        let upper = min(20_000, sampleRate / 2)
        return (0..<bands).map { band in
            let low = 40 * pow(upper / 40, Double(band) / Double(bands))
            let high = 40 * pow(upper / 40, Double(band + 1) / Double(bands))
            let first = max(1, min(n / 2 - 1, Int(low * Double(n) / sampleRate)))
            let last = max(first, min(n / 2 - 1, Int(high * Double(n) / sampleRate)))
            let magnitude = (first...last).map { hypot(real[$0], imaginary[$0]) * 4 / Double(n) }.max() ?? 0
            return Float(max(0, min(1, (20 * log10(max(magnitude, 0.0000001)) + 70) / 70)))
        }
    }
}
