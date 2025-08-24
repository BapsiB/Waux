import Foundation
import AVFoundation

class WaveformProcessingService: ObservableObject {
    private let collectionService: CollectionService
    private let processingQueue = DispatchQueue(label: "waveform.processing.queue")
    private var queuedTrackIds = Set<Int>()
    private var isShuttingDown = false

    init(collectionService: CollectionService) {
        self.collectionService = collectionService
    }

    func analyzeIfMissing(_ track: Track) {
        guard !isShuttingDown else { return }
        guard let id = track.id else { return }
        guard track.waveformData == nil else { return }
        guard !track.isUrl else { return }

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            if self.queuedTrackIds.contains(id) { return }
            self.queuedTrackIds.insert(id)
            self.process(track: track)
        }
    }

    func shutdown() {
        isShuttingDown = true
    }

    private func process(track: Track) {
        defer { queuedTrackIds.remove(track.id ?? -1) }
        let url = URL(fileURLWithPath: track.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try generateWaveform(fromFileAt: url, targetBins: 1024)
            if !data.isEmpty, let id = track.id {
                Task { try await self.collectionService.updateTrackWaveformData(trackId: id, waveformData: data) }
            }
        } catch {
            print("[Waveform] Failed to generate for track id=\(track.id ?? -1): \(error)")
        }
    }

    private func generateWaveform(fromFileAt url: URL, targetBins: Int) throws -> [Double] {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw NSError(domain: "Waveform", code: -1, userInfo: [NSLocalizedDescriptionKey: "No audio track"])
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        if reader.canAdd(output) { reader.add(output) }
        reader.startReading()

        // Estimate total samples using duration and sample rate
        let sampleRate = sampleRateFor(track: track) ?? 44100.0
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let estimatedTotalSamples = max(1, Int(durationSeconds * sampleRate))
        let binsCount = max(1, targetBins)

        var bins = Array(repeating: 0.0, count: binsCount)
        var counts = Array(repeating: 0, count: binsCount)

        var globalSampleIndex = 0

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer() else { break }
            if let blockBuffer = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { (rawBuffer: UnsafeMutableRawBufferPointer) in
                    if let baseAddress = rawBuffer.baseAddress {
                        CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
                    }
                }
                // Int16 interleaved stereo (or mono)
                let sampleCount = length / MemoryLayout<Int16>.size
                data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                    let samples = ptr.bindMemory(to: Int16.self)
                    var i = 0
                    while i < sampleCount {
                        let sample = samples[i]
                        let value = Double(abs(sample)) / Double(Int16.max)
                        // Map to bin index
                        let bin = min(binsCount - 1, Int(Double(globalSampleIndex) * Double(binsCount) / Double(estimatedTotalSamples)))
                        if value > bins[bin] { bins[bin] = value }
                        counts[bin] += 1
                        i += 1
                        globalSampleIndex += 1
                    }
                }
            }
            CMSampleBufferInvalidate(buffer)
        }

        if reader.status == .completed || reader.status == .reading {
            // Normalize bins to 0..1
            let maxVal = bins.max() ?? 1.0
            if maxVal > 0 { bins = bins.map { min(1.0, max(0.0, $0 / maxVal)) } }
            return bins
        } else {
            throw reader.error ?? NSError(domain: "Waveform", code: -2, userInfo: [NSLocalizedDescriptionKey: "Reader failed"])
        }
    }

    private func sampleRateFor(track: AVAssetTrack) -> Double? {
        for fmt in track.formatDescriptions {
            let desc = fmt as! CMAudioFormatDescription
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                return asbd.mSampleRate
            }
        }
        return nil
    }
}


