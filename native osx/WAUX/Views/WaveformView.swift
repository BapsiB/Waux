import SwiftUI

// MARK: - Waveform Service Holder

class WaveformServiceHolder: ObservableObject {
    @Published var service: WaveformProcessingService?
    func ensure(collectionService: CollectionService) {
        if service == nil { service = WaveformProcessingService(collectionService: collectionService) }
    }
}

struct WaveformView: View {
    let waveformData: [Double]
    let progress: Double // 0.0 - 1.0
    let markers: [TimeMarker]
    let durationMs: Int
    var activeColor: Color = AppStyle.mainColor
    var inactiveColor: Color = .gray.opacity(0.5)
    var progressLineColor: Color = AppStyle.mainColor
    var markerColor: Color = AppStyle.mainColor
    var lineWidth: CGFloat = 2.0
    var onTap: ((Double) -> Void)? = nil // Callback for tap events with position ratio

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !waveformData.isEmpty else { return }

                let centerY = size.height / 2.0
                let maxAmplitude = size.height * 0.4

                // Downsample to about half the pixel width like the Flutter code
                let targetPoints = max(1, Int(size.width / 2.0))
                let data = downsample(waveformData, to: targetPoints)
                if data.isEmpty { return }

                let spacing = size.width / CGFloat(max(1, data.count - 1))
                let clampedProgress = max(0.0, min(1.0, progress))
                let splitIndex = Int((clampedProgress * Double(data.count)).rounded(.down))

                var playedPath = Path()
                var unplayedPath = Path()

                for i in 0..<data.count {
                    let x = CGFloat(i) * spacing
                    let amplitude = CGFloat(max(0.0, min(1.0, data[i]))) * maxAmplitude
                    let topY = centerY - amplitude
                    let bottomY = centerY + amplitude

                    if i < splitIndex {
                        playedPath.move(to: CGPoint(x: x, y: topY))
                        playedPath.addLine(to: CGPoint(x: x, y: bottomY))
                    } else {
                        unplayedPath.move(to: CGPoint(x: x, y: topY))
                        unplayedPath.addLine(to: CGPoint(x: x, y: bottomY))
                    }
                }

                context.stroke(playedPath, with: .color(activeColor), lineWidth: lineWidth)
                context.stroke(unplayedPath, with: .color(inactiveColor), lineWidth: lineWidth)

                // Draw markers (full-height bar + small label near the top, to the right of the bar)
                if durationMs > 0 {
                    let labelFont = Font.system(size: 11, weight: .regular)
                    let paddingH: CGFloat = 6
                    let paddingV: CGFloat = 3
                    let elementSpacing: CGFloat = 4
                    let labelTop: CGFloat = 2

                    for marker in markers {
                        let ratio = max(0.0, min(1.0, Double(marker.time) / Double(durationMs)))
                        let x = CGFloat(ratio) * size.width

                        // Marker bar
                        var bar = Path()
                        bar.move(to: CGPoint(x: x, y: 0))
                        bar.addLine(to: CGPoint(x: x, y: size.height))
                        let color = marker.color ?? markerColor
                        context.stroke(bar, with: .color(color), lineWidth: 2)

                        // Label background rect positioned to the right of the bar
                        let text = Text(marker.label)
                            .font(labelFont)
                        let resolved = context.resolve(text)
                        let textSize = resolved.measure(in: CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
                        let bgWidth = min(100, textSize.width) + paddingH * 2
                        let bgHeight = textSize.height + paddingV * 2
                        let bgRect = CGRect(
                            x: min(max(0, x + elementSpacing), size.width - bgWidth),
                            y: labelTop,
                            width: bgWidth,
                            height: bgHeight
                        )

                        let rounded = RoundedRectangle(cornerRadius: 4).path(in: bgRect)
                        context.fill(rounded, with: .color(color.opacity(0.85)))

                        // Draw text centered vertically in bg rect
                        let textPoint = CGPoint(
                            x: bgRect.minX + paddingH,
                            y: bgRect.midY
                        )
                        context.draw(text, at: textPoint, anchor: .leading)
                    }
                }

                // Progress line (on top)
                let progressX = CGFloat(clampedProgress) * size.width
                var progressPath = Path()
                progressPath.move(to: CGPoint(x: progressX, y: 0))
                progressPath.addLine(to: CGPoint(x: progressX, y: size.height))
                context.stroke(progressPath, with: .color(progressLineColor), lineWidth: 2)
            }
            .contentShape(Rectangle()) // Make the entire area tappable
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        guard onTap != nil else { return }
        
        // Calculate the ratio based on x position
        // The waveform bars are distributed across the full width with spacing
        // The last bar is at (data.count - 1) * spacing, which might not reach the very right edge
        // So we should normalize the tap position relative to the actual waveform bounds
        guard !waveformData.isEmpty else { return }
        
        let targetPoints = max(1, Int(size.width / 2.0))
        let data = downsample(waveformData, to: targetPoints)
        if data.isEmpty { return }
        
        let spacing = size.width / CGFloat(max(1, data.count - 1))
        let actualWaveformWidth = CGFloat(data.count - 1) * spacing
        
        // Calculate ratio based on the actual waveform width, not the full view width
        let ratio = max(0.0, min(1.0, location.x / actualWaveformWidth))
        onTap?(ratio)
    }

    private func downsample(_ source: [Double], to targetPoints: Int) -> [Double] {
        guard !source.isEmpty else { return [0.0] }
        guard targetPoints > 0 else { return [0.0] }
        if source.count <= targetPoints { return source }

        var result = Array(repeating: 0.0, count: targetPoints)
        let ratio = Double(source.count) / Double(targetPoints)
        for i in 0..<targetPoints {
            let start = Int(Double(i) * ratio)
            let end = min(Int(Double(i + 1) * ratio), source.count)
            if start >= end {
                result[i] = abs(source[min(start, source.count - 1)])
                continue
            }
            var maxValue = 0.0
            var j = start
            while j < end { // tight loop
                let v = abs(source[j])
                if v > maxValue { maxValue = v }
                j += 1
            }
            result[i] = maxValue
        }
        return result
    }
}

// MARK: - Table Column Component

struct WaveformColumn: View {
    let track: Track
    @ObservedObject var audioService: AudioService
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService
    
    var body: some View {
        // Debug logging to see what's happening
//        let _ = print("[TrackListView] Rendering waveform for track \(track.id ?? -1): hasData=\(track.waveformData != nil), isEmpty=\(track.waveformData?.isEmpty ?? true), bins=\(track.waveformData?.count ?? 0)")
        
        Group {
            if let waveformData = track.waveformData, !waveformData.isEmpty {
                let progress: Double = {
                    if let current = audioService.currentTrack?.id,
                       let id = track.id,
                       current == id,
                       audioService.duration > 0 {
                        return min(1.0, max(0.0, audioService.currentTime / audioService.duration))
                    }
                    return 0.0
                }()
                
                HStack(spacing: 4) {
                    // Play/Pause button
                    Button(action: {
                        handlePlayPauseButtonTap(track: track)
                    }) {
                        Image(systemName: getPlayPauseIcon(for: track))
                            .font(.title2)
                            .foregroundColor(AppStyle.mainColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(getPlayPauseHelpText(for: track))
                    
                    // Waveform view
                    WaveformView(
                        waveformData: waveformData,
                        progress: progress,
                        markers: track.timeMarkers,
                        durationMs: track.duration,
                        onTap: { ratio in
                            handleWaveformTap(track: track, ratio: ratio)
                        }
                    )
                    .frame(height: 36)
                }
            } else {
                // Check if this track is currently being analyzed
                let isCurrentlyAnalyzing = waveformServiceHolder.service?.analyzingTrackIds.contains(track.id ?? -1) ?? false
                
                if isCurrentlyAnalyzing {
                    // Track is currently being analyzed - show progress
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Check if this track has empty waveform data (indicating missing file)
                    // Note: Empty waveform data could also indicate corrupted data that needs regeneration
                    if let waveformData = track.waveformData, waveformData.isEmpty {
                        // For empty waveform data, we need to check if the file actually exists
                        // If the file exists, it means the waveform data is corrupted and needs regeneration
                        // If the file doesn't exist, then it's truly missing
                        let resolvedPath = collectionService.resolveTrackPathForWaveform(track)
                        let url = URL(fileURLWithPath: resolvedPath)
                        let fileExists = FileManager.default.fileExists(atPath: url.path)
                        
                        if fileExists {
                            // File exists but waveform is empty/corrupted - trigger analysis
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Analyzing…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .onAppear {
                                print("[TrackListView] Waveform cell appeared for track \(track.id ?? -1): \(track.title) (regenerating corrupted waveform; fileExists=\(fileExists))")
                                waveformServiceHolder.ensure(collectionService: collectionService)
                                waveformServiceHolder.service?.analyzeIfMissing(track)
                            }
                        } else {
                            // File truly missing
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("File missing")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Analyzing…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .onAppear {
                            print("[TrackListView] Waveform cell appeared for track \(track.id ?? -1): \(track.title) (no waveform present)")
                            waveformServiceHolder.ensure(collectionService: collectionService)
                            waveformServiceHolder.service?.analyzeIfMissing(track)
                        }
                    }
                }
            }
        }
    }
    
    private func handlePlayPauseButtonTap(track: Track) {
        if audioService.currentTrack?.id == track.id {
            // Current track is playing - toggle play/pause
            if audioService.isPlaying {
                audioService.pause()
            } else {
                audioService.play()
            }
        } else {
            // Different track - load and play
            Task {
                await audioService.loadTrack(track)
                audioService.play()
            }
        }
    }
    
    private func getPlayPauseIcon(for track: Track) -> String {
        if audioService.currentTrack?.id == track.id && audioService.isPlaying {
            return "pause.circle.fill"
        } else {
            return "play.circle.fill"
        }
    }
    
    private func getPlayPauseHelpText(for track: Track) -> String {
        if audioService.currentTrack?.id == track.id && audioService.isPlaying {
            return "Pause track"
        } else {
            return "Play track"
        }
    }
    
    private func handleWaveformTap(track: Track, ratio: Double) {
        if audioService.currentTrack?.id == track.id {
            let newTime = Double(track.duration) * ratio
            audioService.play()
            audioService.seek(to: newTime / 1000)
        } else {
            Task {
                await audioService.loadTrack(track)
                audioService.play()
                let newTime = Double(track.duration) * ratio
                audioService.seek(to: newTime / 1000)
            }
        }
    }
}


