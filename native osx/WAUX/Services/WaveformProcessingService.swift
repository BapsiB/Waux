import Foundation
import AVFoundation

class WaveformProcessingService: ObservableObject {
    private let collectionService: CollectionService
    private let processingQueue = DispatchQueue(label: "waveform.processing.queue")
    private var queuedTrackIds = Set<Int>()
    private var isShuttingDown = false

    init(collectionService: CollectionService) {
        self.collectionService = collectionService
        print("[Waveform] Service initialized")
    }

    func analyzeIfMissing(_ track: Track) {
        guard !isShuttingDown else { 
            print("[Waveform] Service is shutting down, ignoring track \(track.id ?? -1)")
            return 
        }
        guard let id = track.id else { 
            print("[Waveform] Track has no ID, ignoring: \(track.title)")
            return 
        }
        guard track.waveformData == nil else { 
            print("[Waveform] Track \(id) already has waveform data, skipping")
            return 
        }
        guard !track.isUrl else { 
            print("[Waveform] Track \(id) is URL, skipping waveform analysis")
            return 
        }

        print("[Waveform] Starting analysis for track \(id): \(track.title)")
        print("[Waveform] Track path: \(track.path)")
        print("[Waveform] Track duration: \(track.duration) ms")

        processingQueue.async { [weak self] in
            guard let self = self else { 
                print("[Waveform] Self is nil, aborting analysis for track \(id)")
                return 
            }
            if self.queuedTrackIds.contains(id) { 
                print("[Waveform] Track \(id) already queued, skipping")
                return 
            }
            self.queuedTrackIds.insert(id)
            print("[Waveform] Added track \(id) to processing queue. Queue size: \(self.queuedTrackIds.count)")
            self.process(track: track)
        }
    }

    func shutdown() {
        print("[Waveform] Shutting down service")
        isShuttingDown = true
    }

    private func process(track: Track) {
        let trackId = track.id ?? -1
        print("[Waveform] Processing track \(trackId): \(track.title)")
        
        defer { 
            queuedTrackIds.remove(trackId)
            print("[Waveform] Removed track \(trackId) from queue. Remaining: \(queuedTrackIds.count)")
        }
        
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
                Task {
                    do {
                        // Store empty waveform data to indicate file is missing
                        try await self.collectionService.updateTrackWaveformData(trackId: id, waveformData: [])
                        print("[Waveform] ✅ Marked track \(id) as having missing file")
                    } catch {
                        print("[Waveform] ❌ Failed to mark track \(id) as missing: \(error)")
                    }
                }
            }
            return 
        }

        print("[Waveform] ✅ File exists for track \(trackId): \(url.path)")

        do {
            print("[Waveform] 🎵 Generating waveform for track \(trackId)...")
            let data = try generateWaveform(fromFileAt: url, targetBins: 1024)
            print("[Waveform] ✅ Generated waveform for track \(trackId): \(data.count) bins")
            
            if !data.isEmpty, let id = track.id {
                print("[Waveform] 💾 Saving waveform data for track \(id)...")
                Task { 
                    do {
                        try await self.collectionService.updateTrackWaveformData(trackId: id, waveformData: data)
                        print("[Waveform] ✅ Successfully saved waveform data for track \(id)")
                    } catch {
                        print("[Waveform] ❌ Failed to save waveform data for track \(id): \(error)")
                    }
                }
            } else {
                print("[Waveform] ⚠️ Generated waveform data is empty for track \(trackId)")
            }
        } catch {
            print("[Waveform] ❌ Failed to generate waveform for track \(trackId): \(error)")
        }
    }

    private func generateWaveform(fromFileAt url: URL, targetBins: Int) throws -> [Double] {
        print("[Waveform] 📁 Creating AVAsset from: \(url.path)")
        
        // Check file permissions and size first
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            print("[Waveform] ❌ File does not exist at path: \(url.path)")
            throw NSError(domain: "Waveform", code: -3, userInfo: [NSLocalizedDescriptionKey: "File does not exist"])
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            print("[Waveform] 📊 File size: \(fileSize) bytes")
            
            if fileSize == 0 {
                print("[Waveform] ❌ File is empty")
                throw NSError(domain: "Waveform", code: -4, userInfo: [NSLocalizedDescriptionKey: "File is empty"])
            }
        } catch {
            print("[Waveform] ❌ Cannot read file attributes: \(error)")
            throw NSError(domain: "Waveform", code: -5, userInfo: [NSLocalizedDescriptionKey: "Cannot read file attributes"])
        }
        
        let asset = AVAsset(url: url)
        
        // Wait for the asset to be loadable
        let loadableKey = "tracks"
        let loadableGroup = DispatchGroup()
        loadableGroup.enter()
        
        asset.loadValuesAsynchronously(forKeys: [loadableKey]) {
            defer { loadableGroup.leave() }
        }
        
        // Wait with timeout
        let result = loadableGroup.wait(timeout: .now() + 5.0)
        if result == .timedOut {
            print("[Waveform] ❌ Timeout waiting for asset to load")
            throw NSError(domain: "Waveform", code: -6, userInfo: [NSLocalizedDescriptionKey: "Asset loading timeout"])
        }
        
        // Check if asset loaded successfully
        var error: NSError?
        let status = asset.statusOfValue(forKey: loadableKey, error: &error)
        if status == .failed {
            print("[Waveform] ❌ Failed to load asset: \(error?.localizedDescription ?? "Unknown error")")
            
            // Check if it's a permission error and try fallback
            if let error = error, error.domain == NSCocoaErrorDomain && error.code == 257 {
                print("[Waveform] 🔄 Permission error detected, trying AVAudioFile fallback...")
                return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
            }
            
            throw error ?? NSError(domain: "Waveform", code: -7, userInfo: [NSLocalizedDescriptionKey: "Asset loading failed"])
        }
        
        print("[Waveform] 🎧 Getting audio tracks...")
        let audioTracks = asset.tracks(withMediaType: .audio)
        print("[Waveform] 📊 Found \(audioTracks.count) audio tracks")
        
        guard let track = audioTracks.first else {
            print("[Waveform] ❌ No audio track found in file")
            print("[Waveform] 🔍 Available tracks:")
            let allTracks = asset.tracks
            for (index, t) in allTracks.enumerated() {
                print("[Waveform]   Track \(index): \(t.mediaType.rawValue)")
            }
            
            // Try fallback method immediately
            print("[Waveform] 🔄 Trying fallback method immediately...")
            return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
        }
        print("[Waveform] ✅ Found audio track")

        print("[Waveform] 📖 Creating AVAssetReader...")
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
        if reader.canAdd(output) { 
            reader.add(output)
            print("[Waveform] ✅ Added output to reader")
        } else {
            print("[Waveform] ❌ Cannot add output to reader")
        }
        
        print("[Waveform] ▶️ Starting reader...")
        reader.startReading()

        // Estimate total samples using duration and sample rate
        let sampleRate = sampleRateFor(track: track) ?? 44100.0
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        let estimatedTotalSamples = max(1, Int(durationSeconds * sampleRate))
        let binsCount = max(1, targetBins)

        print("[Waveform] 📊 Sample rate: \(sampleRate), Duration: \(durationSeconds)s, Estimated samples: \(estimatedTotalSamples), Bins: \(binsCount)")

        var bins = Array(repeating: 0.0, count: binsCount)
        var counts = Array(repeating: 0, count: binsCount)

        var globalSampleIndex = 0
        var bufferCount = 0

        print("[Waveform] 🔄 Starting to read sample buffers...")
        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer() else { 
                print("[Waveform] 📭 No more sample buffers available")
                break 
            }
            
            bufferCount += 1
            if bufferCount % 100 == 0 {
                print("[Waveform] 📦 Processed \(bufferCount) buffers, \(globalSampleIndex) samples")
            }
            
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
                        // Safe absolute value calculation to avoid overflow with -32768
                        let absValue: Int32
                        if sample == Int16.min {
                            absValue = Int32(Int16.max) + 1
                        } else {
                            absValue = Int32(abs(sample))
                        }
                        let value = Double(absValue) / Double(Int16.max)
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

        print("[Waveform] 📊 Final stats: \(bufferCount) buffers, \(globalSampleIndex) samples processed")
        print("[Waveform] 📈 Reader status: \(reader.status.rawValue)")

        if reader.status == .completed || reader.status == .reading {
            // Normalize bins to 0..1
            let maxVal = bins.max() ?? 1.0
            if maxVal > 0 { bins = bins.map { min(1.0, max(0.0, $0 / maxVal)) } }
            print("[Waveform] ✅ Waveform generation completed successfully")
            return bins
        } else {
            let error = reader.error
            print("[Waveform] ❌ Reader failed with status: \(reader.status.rawValue)")
            if let error = error {
                print("[Waveform] ❌ Reader error: \(error)")
            }
            
            // Try fallback method using AVAudioFile
            print("[Waveform] 🔄 Trying fallback method with AVAudioFile...")
            return try generateWaveformFallback(fromFileAt: url, targetBins: targetBins)
        }
    }
    
    private func generateWaveformFallback(fromFileAt url: URL, targetBins: Int) throws -> [Double] {
        print("[Waveform] 🎵 Using AVAudioFile fallback method...")
        
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = UInt32(audioFile.length)
            
            print("[Waveform] 📊 Audio file format: \(format)")
            print("[Waveform] 📊 Frame count: \(frameCount)")
            
            if frameCount == 0 {
                print("[Waveform] ❌ Audio file has no frames")
                throw NSError(domain: "Waveform", code: -8, userInfo: [NSLocalizedDescriptionKey: "Audio file has no frames"])
            }
            
            // Read the entire file into a buffer
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            try audioFile.read(into: buffer)
            
            guard let channelData = buffer.floatChannelData else {
                print("[Waveform] ❌ No channel data available")
                throw NSError(domain: "Waveform", code: -9, userInfo: [NSLocalizedDescriptionKey: "No channel data"])
            }
            
            let binsCount = max(1, targetBins)
            var bins = Array(repeating: 0.0, count: binsCount)
            var counts = Array(repeating: 0, count: binsCount)
            
            // Process samples
            let samplesPerBin = Int(frameCount) / binsCount
            for binIndex in 0..<binsCount {
                let startSample = binIndex * samplesPerBin
                let endSample = min(startSample + samplesPerBin, Int(frameCount))
                
                var maxAmplitude: Float = 0.0
                for sampleIndex in startSample..<endSample {
                    // Average across all channels
                    var sampleValue: Float = 0.0
                    for channel in 0..<Int(format.channelCount) {
                        sampleValue += abs(channelData[channel][sampleIndex])
                    }
                    sampleValue /= Float(format.channelCount)
                    maxAmplitude = max(maxAmplitude, sampleValue)
                }
                
                bins[binIndex] = Double(maxAmplitude)
                counts[binIndex] = endSample - startSample
            }
            
            // Normalize bins to 0..1
            let maxVal = bins.max() ?? 1.0
            if maxVal > 0 { bins = bins.map { min(1.0, max(0.0, $0 / maxVal)) } }
            
            print("[Waveform] ✅ Fallback waveform generation completed successfully")
            return bins
            
        } catch {
            print("[Waveform] ❌ Fallback method also failed: \(error)")
            throw error
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


