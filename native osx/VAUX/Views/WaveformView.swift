import SwiftUI

// MARK: - Waveform Service Holder

class WaveformServiceHolder: ObservableObject {
    @Published var service: WaveformProcessingService?
    func ensure(collectionService: CollectionService) {
        if service == nil { service = WaveformProcessingService(collectionService: collectionService) }
    }
}

struct WaveformView: View {
    /// When `true`, bar count follows view width (~one bar per two points). When `false`, a fixed compact bar count is used (list rows when not actively playing this track).
    var highDetail: Bool = true
    /// Fixed number of vertical bars used when `highDetail` is `false`.
    static let compactListBarCount: Int = 96

    let waveformData: [Double]
    let progress: Double // 0.0 - 1.0
    let markers: [TimeMarker]
    let durationMs: Int
    var isPlaying: Bool = false // Whether the sound is currently playing
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

                let targetPoints = targetPointCount(forWidth: size.width)
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


            }
            .contentShape(Rectangle()) // Make the entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { gesture in
                        handleTap(at: gesture.location, in: geo.size)
                    }
            )
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        guard onTap != nil else { return }
        
        // Calculate the ratio based on x position
        // The waveform bars are distributed across the full width with spacing
        // The last bar is at (data.count - 1) * spacing, which might not reach the very right edge
        // So we should normalize the tap position relative to the actual waveform bounds
        guard !waveformData.isEmpty else { 
            print("[WaveformView] handleTap: waveformData is empty")
            return 
        }
        
        let targetPoints = targetPointCount(forWidth: size.width)
        let data = downsample(waveformData, to: targetPoints)
        if data.isEmpty { 
            print("[WaveformView] handleTap: downsampled data is empty")
            return 
        }
        
        let spacing = size.width / CGFloat(max(1, data.count - 1))
        let actualWaveformWidth = CGFloat(data.count - 1) * spacing
        
        // Calculate ratio based on the actual waveform width, not the full view width
        let ratio = max(0.0, min(1.0, location.x / actualWaveformWidth))
        
        // Concise logging for debugging tap issues (NEW VERSION)
        print("🎯 [WaveformView] TAP: x=\(Int(location.x))/\(Int(size.width)) → ratio=\(String(format: "%.3f", ratio)) (\(Int(ratio * 100))%)")
        print("  📊 Data: \(waveformData.count)→\(data.count) points, spacing=\(String(format: "%.1f", spacing)), width=\(String(format: "%.1f", actualWaveformWidth))")
        
        onTap?(ratio)
    }

    private func targetPointCount(forWidth width: CGFloat) -> Int {
        if highDetail {
            return max(1, Int(width / 2.0))
        }
        return Self.compactListBarCount
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

/// Play/pause + waveform for a track row. `Equatable` so SwiftUI skips redundant redraws when only other rows' playback state changes.
private struct WaveformListCell: View, Equatable {
    let track: Track
    let playbackProgress: Double
    let isPlayingThisTrack: Bool
    let highDetailWaveform: Bool
    let audioService: AudioService

    static func == (lhs: WaveformListCell, rhs: WaveformListCell) -> Bool {
        guard lhs.track.id == rhs.track.id else { return false }
        guard lhs.track.waveformPointCount == rhs.track.waveformPointCount else { return false }
        guard lhs.track.timeMarkers.count == rhs.track.timeMarkers.count else { return false }
        guard lhs.isPlayingThisTrack == rhs.isPlayingThisTrack else { return false }
        guard lhs.highDetailWaveform == rhs.highDetailWaveform else { return false }
        return abs(lhs.playbackProgress - rhs.playbackProgress) < 0.0001
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                handlePlayPauseButtonTap(track: track)
            }) {
                Image(systemName: isPlayingThisTrack ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(AppStyle.mainColor)
            }
            .buttonStyle(PlainButtonStyle())
            .help(isPlayingThisTrack ? "Pause track" : "Play track")

            WaveformView(
                highDetail: highDetailWaveform,
                waveformData: track.waveformData ?? [],
                progress: playbackProgress,
                markers: track.timeMarkers,
                durationMs: track.duration,
                isPlaying: isPlayingThisTrack,
                onTap: { ratio in
                    handleWaveformTap(track: track, ratio: ratio)
                }
            )
            .frame(height: 36)
        }
    }

    private func handlePlayPauseButtonTap(track: Track) {
        if audioService.currentTrack?.id == track.id {
            if audioService.isPlaying {
                audioService.pause()
            } else {
                audioService.play()
            }
        } else {
            Task {
                _ = await audioService.loadTrack(track)
                audioService.play()
            }
        }
    }

    private func handleWaveformTap(track: Track, ratio: Double) {
        print("🎵 [WaveformColumn] SEEK: Track \(track.id ?? -1) '\(track.title)'")
        print("  ⏱️ Stored: \(track.duration)ms (\(track.duration/1000)s) | Current Audio: \(String(format: "%.1f", audioService.duration))s | Ratio: \(String(format: "%.3f", ratio))")

        if audioService.currentTrack?.id == track.id {
            let seekTimeSeconds = audioService.duration * ratio
            print("  🎯 Current track seek: \(String(format: "%.1f", seekTimeSeconds))s")
            audioService.play()
            audioService.seek(to: seekTimeSeconds)
        } else {
            Task {
                let player = await audioService.loadTrack(track)
                audioService.play()

                if let player = player {
                    player.currentTime = 0.0
                    let correctDuration = player.duration

                    let seekTimeSeconds = correctDuration * ratio
                    print("  🎯 New track seek: \(String(format: "%.1f", seekTimeSeconds))s (correct duration: \(String(format: "%.1f", correctDuration))s)")
                    audioService.seek(to: seekTimeSeconds)

                    let correctDuration2 = player.duration
                    if abs(correctDuration2 - correctDuration) > 1.0 {
                        let seekTimeSeconds = correctDuration2 * ratio
                        print("  🎯 New track seek: \(String(format: "%.1f", seekTimeSeconds))s (correct duration: \(String(format: "%.1f", correctDuration))s)")
                        audioService.seek(to: seekTimeSeconds)
                    }
                } else {
                    print("  ❌ Failed to load track")
                }
            }
        }
    }
}

struct WaveformColumn: View {
    let track: Track
    let playbackProgress: Double
    let isPlayingThisTrack: Bool
    let highDetailWaveform: Bool
    let audioService: AudioService
    @ObservedObject var waveformServiceHolder: WaveformServiceHolder
    @ObservedObject var collectionService: CollectionService

    /// Compute at the table level (single `AudioService` observation) and pass into each row so cells do not subscribe to timer-driven playback updates.
    static func playbackParameters(track: Track, audioService: AudioService) -> (progress: Double, isPlayingThisTrack: Bool, highDetailWaveform: Bool) {
        guard let tid = track.id, let currentId = audioService.currentTrack?.id, tid == currentId else {
            return (0, false, false)
        }
        let progress = audioService.duration > 0
            ? min(1.0, max(0.0, audioService.currentTime / audioService.duration))
            : 0.0
        let isPlayingThisTrack = audioService.isPlaying
        let highDetailWaveform = isPlayingThisTrack
        return (progress, isPlayingThisTrack, highDetailWaveform)
    }
    
    var body: some View {
        Group {
            if track.waveformData?.isEmpty == false {
                WaveformListCell(
                    track: track,
                    playbackProgress: playbackProgress,
                    isPlayingThisTrack: isPlayingThisTrack,
                    highDetailWaveform: highDetailWaveform,
                    audioService: audioService
                )
                .equatable()
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
}


