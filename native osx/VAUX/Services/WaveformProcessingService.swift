import Foundation
import AVFoundation
import Accelerate
import Combine

class WaveformProcessingService: ObservableObject {
    private let collectionService: CollectionService
    private let status: WaveformStatusModel
    private let processingQueue = DispatchQueue(label: "waveform.processing.queue")
    private var pendingIds: [Int] = []
    private var pendingIdSet = Set<Int>()
    private var trackById: [Int: Track] = [:]
    private var isPumpRunning = false
    private var isShuttingDown = false
    private var analyzingTrackIds = Set<Int>()
    private var tracksCancellable: AnyCancellable?

    init(collectionService: CollectionService, status: WaveformStatusModel) {
        self.collectionService = collectionService
        self.status = status
        print("[Waveform] Service initialized")
        tracksCancellable = collectionService.tracksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.enqueueAllMissing()
            }
    }

    /// Queue a specific track (refresh, regenerate, corrupted empty waveform).
    func analyzeIfMissing(_ track: Track) {
        guard !isShuttingDown else {
            print("[Waveform] Service is shutting down, ignoring track \(track.id ?? -1)")
            return
        }
        guard let id = track.id else {
            print("[Waveform] Track has no ID, ignoring: \(track.title)")
            return
        }
        let hasWaveform = track.waveformData != nil && !(track.waveformData?.isEmpty ?? true)
        print("[Waveform] Analyze gate for track \(id): waveformPresent=\(track.waveformData != nil), waveformEmpty=\(track.waveformData?.isEmpty ?? true), willAnalyze=\(!hasWaveform)")
        guard !hasWaveform else {
            print("[Waveform] Track \(id) already has valid waveform data (\(track.waveformData?.count ?? 0) bins), skipping")
            return
        }
        guard !track.isUrl else {
            print("[Waveform] Track \(id) is URL, skipping waveform analysis")
            return
        }

        print("[Waveform] Queueing analysis for track \(id): \(track.title)")
        enqueue(tracks: [track])
    }

    /// Queue every local track with no waveform. Independent of table visibility.
    func enqueueAllMissing() {
        guard !isShuttingDown else { return }
        let missing = collectionService.tracks.filter { track in
            !track.isUrl && track.waveformData == nil && track.id != nil
        }
        if !missing.isEmpty {
            print("[Waveform] Scanning collection for missing waveforms: \(missing.count) of \(collectionService.tracks.count)")
        }
        enqueue(tracks: missing)
    }

    private func enqueue(tracks: [Track]) {
        processingQueue.async { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            var added = 0
            for track in tracks {
                guard let id = track.id else { continue }
                self.trackById[id] = track
                if self.pendingIdSet.insert(id).inserted {
                    self.pendingIds.append(id)
                    added += 1
                }
            }
            if added > 0 {
                print("[Waveform] Added \(added) tracks to analysis queue. Pending: \(self.pendingIds.count)")
            }
            self.startPumpIfNeededLocked()
        }
    }

    private func startPumpIfNeededLocked() {
        guard !isPumpRunning, !pendingIds.isEmpty, !isShuttingDown else { return }
        isPumpRunning = true
        print("[Waveform] Starting analysis pump with \(pendingIds.count) tracks")
        processNextLocked()
    }

    /// Process one pending track, then yield so newly enqueued tracks can join the queue.
    private func processNextLocked() {
        guard !isShuttingDown else {
            isPumpRunning = false
            return
        }
        guard !pendingIds.isEmpty else {
            isPumpRunning = false
            print("[Waveform] Analysis pump idle")
            return
        }

        let id = pendingIds.removeFirst()
        pendingIdSet.remove(id)
        guard let track = trackById.removeValue(forKey: id) else {
            print("[Waveform] Track \(id) no longer in collection, skipping")
            processingQueue.async { [weak self] in self?.processNextLocked() }
            return
        }

        let hasWaveform = track.waveformData != nil && !(track.waveformData?.isEmpty ?? true)
        if hasWaveform {
            processingQueue.async { [weak self] in self?.processNextLocked() }
            return
        }

        print("[Waveform] Starting analysis for track \(id): \(track.title)")
        print("[Waveform] Track path: \(track.path)")
        print("[Waveform] Track duration: \(track.duration) ms")
        markAnalyzing(id)
        process(track: track)
        unmarkAnalyzing(id)
        processingQueue.async { [weak self] in self?.processNextLocked() }
    }

    private func markAnalyzing(_ id: Int) {
        let apply = {
            self.analyzingTrackIds.insert(id)
            self.status.analyzingCount = self.analyzingTrackIds.count
            print("[Waveform] Added track \(id) to analyzing set")
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func unmarkAnalyzing(_ id: Int) {
        let apply = {
            self.analyzingTrackIds.remove(id)
            self.status.analyzingCount = self.analyzingTrackIds.count
            print("[Waveform] Removed track \(id) from analyzing set")
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func shutdown() {
        print("[Waveform] Shutting down service")
        isShuttingDown = true
    }
    
    func clearAllWaveformData() {
        print("[Waveform] Clearing all waveform data to regenerate with time-based mapping")
        Task {
            do {
                try await collectionService.clearAllWaveformData()
                print("[Waveform] ✅ All waveform data cleared")
            } catch {
                print("[Waveform] ❌ Failed to clear waveform data: \(error)")
            }
        }
    }

    private func process(track: Track) {
        let trackId = track.id ?? -1
        print("[Waveform] Processing track \(trackId): \(track.title)")
        print("[Waveform] Remaining in queue: \(pendingIds.count)")
        
        // Try to resolve the path using CollectionService's path resolution
        let resolvedPath = collectionService.resolveTrackPathForWaveform(track)
        print("[Waveform] 🔍 Original path: \(track.path)")
        print("[Waveform] 🔍 Resolved path: \(resolvedPath)")
        
        let url = URL(fileURLWithPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: url.path) else { 
            print("[Waveform] ❌ File does not exist for track \(trackId): \(url.path)")
            print("[Waveform] 🔍 Collection root folders: \(collectionService.getRootFolders())")
            
            // Mark this track as having a missing file to prevent infinite retries
            // We'll store an empty waveform data to indicate the file is missing
            if let id = track.id {
                print("[Waveform] 🏷️ Marking track \(id) as having missing file")
                saveWaveformSync(trackId: id, waveformData: [], successLog: "Marked track \(id) as having missing file")
            }
            return 
        }

        print("[Waveform] ✅ File exists for track \(trackId): \(url.path)")

        do {
            let data = try generateWaveform(fromFileAt: url, targetBins: 1024)
            
            if !data.isEmpty, let id = track.id {
                saveWaveformSync(trackId: id, waveformData: data, successLog: "Successfully saved waveform data for track \(id)")
            } else {
                print("[Waveform] ⚠️ Generated waveform data is empty for track \(trackId)")
            }
        } catch {
            print("[Waveform] ❌ Failed to generate waveform for track \(trackId): \(error)")
        }
    }

    private func saveWaveformSync(trackId: Int, waveformData: [Double], successLog: String) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                try await self.collectionService.updateTrackWaveformData(trackId: trackId, waveformData: waveformData)
                print("[Waveform] ✅ \(successLog)")
            } catch {
                print("[Waveform] ❌ Failed to save waveform for track \(trackId): \(error)")
            }
        }
        semaphore.wait()
    }

    private func generateWaveform(fromFileAt url: URL, targetBins: Int) throws -> [Double] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "Waveform", code: -3, userInfo: [NSLocalizedDescriptionKey: "File does not exist"])
        }

        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        if fileSize == 0 {
            throw NSError(domain: "Waveform", code: -4, userInfo: [NSLocalizedDescriptionKey: "File is empty"])
        }

        let asset = AVAsset(url: url)

        let loadableKey = "tracks"
        let loadableGroup = DispatchGroup()
        loadableGroup.enter()
        asset.loadValuesAsynchronously(forKeys: [loadableKey]) {
            loadableGroup.leave()
        }

        let result = loadableGroup.wait(timeout: .now() + 5.0)
        if result == .timedOut {
            print("[Waveform] ❌ Timeout waiting for asset to load")
            throw NSError(domain: "Waveform", code: -6, userInfo: [NSLocalizedDescriptionKey: "Asset loading timeout"])
        }

        var error: NSError?
        let status = asset.statusOfValue(forKey: loadableKey, error: &error)
        if status == .failed {
            print("[Waveform] ❌ Failed to load asset: \(error?.localizedDescription ?? "Unknown error")")
            if let error = error, error.domain == NSCocoaErrorDomain && error.code == 257 {
                print("[Waveform] 🔄 Permission error detected, trying AVAudioFile fallback...")
                return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
            }
            throw error ?? NSError(domain: "Waveform", code: -7, userInfo: [NSLocalizedDescriptionKey: "Asset loading failed"])
        }

        let audioTracks = asset.tracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            print("[Waveform] ❌ No audio track found, trying fallback...")
            return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
        }

        let reader = try AVAssetReader(asset: asset)
        // Mono float at the file's native sample rate: no stereo doubling, no resample.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            print("[Waveform] ❌ Cannot add output to reader, trying fallback...")
            return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
        }
        reader.add(output)

        guard reader.startReading() else {
            print("[Waveform] ❌ Failed to start reader, trying fallback...")
            return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
        }

        let sampleRate = sampleRateFor(track: track) ?? Double(track.naturalTimeScale)
        var durationSeconds = CMTimeGetSeconds(asset.duration)
        if !durationSeconds.isFinite || durationSeconds <= 0 {
            durationSeconds = CMTimeGetSeconds(track.timeRange.duration)
        }
        guard durationSeconds.isFinite, durationSeconds > 0, sampleRate > 0 else {
            print("[Waveform] ❌ Invalid duration/sample rate, trying fallback...")
            return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
        }

        let binsCount = max(1, targetBins)
        let totalFrames = max(1, Int((durationSeconds * sampleRate).rounded()))
        var bins = [Float](repeating: 0, count: binsCount)
        var copyScratch: [Float] = []
        var frameIndex = 0

        print("[Waveform] 📊 Duration: \(durationSeconds)s, Sample rate: \(sampleRate), Bins: \(binsCount), Frames: \(totalFrames)")

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(buffer) }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
            withFloatSamples(from: blockBuffer, copyScratch: &copyScratch) { samples, count in
                accumulateMaxMagnitudes(
                    samples: samples,
                    count: count,
                    stride: 1,
                    startFrame: frameIndex,
                    totalFrames: totalFrames,
                    bins: &bins
                )
                frameIndex += count
            }
        }

        if reader.status == .completed || reader.status == .reading {
            print("[Waveform] ✅ Waveform generation completed (\(frameIndex) frames)")
            return normalizedBins(bins)
        }

        print("[Waveform] ❌ Reader failed with status: \(reader.status.rawValue), trying fallback...")
        if let readerError = reader.error {
            print("[Waveform] ❌ Reader error: \(readerError)")
        }
        return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
    }
    
    private func generateWaveformFallback(fromFileAt url: URL, targetBins: Int) throws -> [Double] {
        print("[Waveform] 🎵 Using AVAudioFile fallback method...")

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let totalFrames = Int(audioFile.length)
            guard totalFrames > 0 else {
                throw NSError(domain: "Waveform", code: -8, userInfo: [NSLocalizedDescriptionKey: "Audio file has no frames"])
            }

            let chunkFrames: AVAudioFrameCount = 32_768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
                throw NSError(domain: "Waveform", code: -9, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
            }

            let binsCount = max(1, targetBins)
            var bins = [Float](repeating: 0, count: binsCount)
            let channelCount = Int(format.channelCount)
            var frameIndex = 0

            print("[Waveform] 📊 Fallback: \(totalFrames) frames, \(channelCount) ch, \(format.sampleRate) Hz")

            while frameIndex < totalFrames {
                try audioFile.read(into: buffer)
                let framesRead = Int(buffer.frameLength)
                if framesRead <= 0 { break }

                guard let channels = buffer.floatChannelData else {
                    throw NSError(domain: "Waveform", code: -9, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
                }

                let stride = format.isInterleaved ? channelCount : 1
                let channelStep = format.isInterleaved ? 1 : 0
                for ch in 0..<channelCount {
                    let pointer = channels[format.isInterleaved ? 0 : ch].advanced(by: ch * channelStep)
                    accumulateMaxMagnitudes(
                        samples: pointer,
                        count: framesRead,
                        stride: stride,
                        startFrame: frameIndex,
                        totalFrames: totalFrames,
                        bins: &bins
                    )
                }
                frameIndex += framesRead
            }

            print("[Waveform] ✅ Fallback waveform generation completed (\(frameIndex) frames)")
            return normalizedBins(bins)
        } catch {
            print("[Waveform] ❌ Fallback method also failed: \(error)")
            throw error
        }
    }

    /// Peak-magnitude reduction: one vDSP call per bin-aligned slice.
    private func accumulateMaxMagnitudes(
        samples: UnsafePointer<Float>,
        count: Int,
        stride: Int,
        startFrame: Int,
        totalFrames: Int,
        bins: inout [Float]
    ) {
        let binsCount = bins.count
        guard count > 0, totalFrames > 0, binsCount > 0, stride > 0 else { return }

        var offset = 0
        while offset < count {
            let frame = startFrame + offset
            if frame >= totalFrames {
                var peak: Float = 0
                vDSP_maxmgv(
                    samples.advanced(by: offset * stride),
                    vDSP_Stride(stride),
                    &peak,
                    vDSP_Length(count - offset)
                )
                let last = binsCount - 1
                if peak > bins[last] { bins[last] = peak }
                return
            }

            let bin = min(binsCount - 1, frame * binsCount / totalFrames)
            // Smallest frame at which integer mapping enters the next bin:
            // frame * binsCount / totalFrames >= bin + 1
            let nextBinStart = ((bin + 1) * totalFrames + binsCount - 1) / binsCount
            let sliceEndFrame = min(startFrame + count, max(nextBinStart, frame + 1), totalFrames)
            let sliceCount = sliceEndFrame - frame
            guard sliceCount > 0 else { return }

            var peak: Float = 0
            vDSP_maxmgv(
                samples.advanced(by: offset * stride),
                vDSP_Stride(stride),
                &peak,
                vDSP_Length(sliceCount)
            )
            if peak > bins[bin] { bins[bin] = peak }
            offset += sliceCount
        }
    }

    private func normalizedBins(_ bins: [Float]) -> [Double] {
        let maxVal = bins.max() ?? 1
        guard maxVal > 0 else {
            return [Double](repeating: 0, count: bins.count)
        }
        return bins.map { Double(min(1, max(0, $0 / maxVal))) }
    }

    /// Prefer in-place CMBlockBuffer access; copy only when the buffer is non-contiguous.
    private func withFloatSamples(
        from blockBuffer: CMBlockBuffer,
        copyScratch: inout [Float],
        body: (UnsafePointer<Float>, Int) -> Void
    ) {
        let byteLength = CMBlockBufferGetDataLength(blockBuffer)
        let floatCount = byteLength / MemoryLayout<Float>.stride
        guard floatCount > 0 else { return }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        if status == kCMBlockBufferNoErr, let dataPointer, lengthAtOffset >= byteLength {
            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { pointer in
                body(pointer, floatCount)
            }
            return
        }

        if copyScratch.count < floatCount {
            copyScratch = [Float](repeating: 0, count: floatCount)
        }
        let copyStatus = copyScratch.withUnsafeMutableBytes { raw -> OSStatus in
            guard let destination = raw.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteLength,
                destination: destination
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else { return }
        copyScratch.withUnsafeBufferPointer { buffer in
            guard let pointer = buffer.baseAddress else { return }
            body(pointer, floatCount)
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
