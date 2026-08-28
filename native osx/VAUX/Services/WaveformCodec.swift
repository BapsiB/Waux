import Foundation

/// Packed Float32 waveform samples stored in the `waveforms` table.
enum WaveformCodec {
    static let binCount = 256
    static let blobVersion = 1

    static func encode(_ bins: [Double]) -> Data {
        var floats = bins.map { Float($0) }
        return floats.withUnsafeBytes { Data($0) }
    }

    static func decode(_ data: Data) -> [Double] {
        let stride = MemoryLayout<Float>.stride
        let count = data.count / stride
        guard count > 0 else { return [] }
        return data.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: Float.self)
            return (0..<count).map { Double(buffer[$0]) }
        }
    }

    /// Peak-preserving resample used when migrating legacy 1024-bin JSON to 256 bins.
    static func downsample(_ source: [Double], to target: Int) -> [Double] {
        guard target > 0 else { return [] }
        if source.isEmpty { return [] }
        if source.count == target { return source }
        if source.count < target {
            var result = [Double](repeating: 0, count: target)
            let ratio = Double(source.count) / Double(target)
            for i in 0..<target {
                let index = min(source.count - 1, Int(Double(i) * ratio))
                result[i] = abs(source[index])
            }
            return result
        }

        var result = [Double](repeating: 0, count: target)
        let ratio = Double(source.count) / Double(target)
        for i in 0..<target {
            let start = Int(Double(i) * ratio)
            let end = min(Int(Double(i + 1) * ratio), source.count)
            if start >= end {
                result[i] = abs(source[min(start, source.count - 1)])
                continue
            }
            var maxValue = 0.0
            var j = start
            while j < end {
                let v = abs(source[j])
                if v > maxValue { maxValue = v }
                j += 1
            }
            result[i] = maxValue
        }
        return result
    }
}
