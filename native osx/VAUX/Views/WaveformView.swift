import SwiftUI
import Combine

// MARK: - Waveform Service Holder

final class WaveformStatusModel: ObservableObject {
    @Published var missingCount = 0
    @Published var analyzingCount = 0
}

final class TrackWaveformSlot: ObservableObject {
    @Published var data: [Double]?
}

final class WaveformDataStore {
    private var slots: [Int: TrackWaveformSlot] = [:]
    /// Rows enqueued because they became visible; always served before bulk prewarm loads.
    private var priorityIds: Set<Int> = []
    /// Bulk prewarm loads, processed in small chunks so scrolling stays responsive.
    private var queuedIds: Set<Int> = []
    private var resolvedIds: Set<Int> = []
    private var flushTask: Task<Void, Never>?
    private static let chunkSize = 400
    private static let bulkChunkPauseNanos: UInt64 = 8_000_000
    weak var collectionService: CollectionService?

    func slot(for id: Int, loadIfNeeded: Bool = true) -> TrackWaveformSlot {
        if let existing = slots[id] {
            if loadIfNeeded { enqueueLoad(id) }
            return existing
        }
        let slot = TrackWaveformSlot()
        slots[id] = slot
        if loadIfNeeded {
            enqueueLoad(id)
        }
        return slot
    }

    /// Schedules background loads for the given ids so rows are populated before
    /// they scroll into view. Loads requested via `slot(for:)` (visible rows)
    /// keep priority over this bulk queue.
    func prewarm(ids: [Int]) {
        guard collectionService != nil else { return }
        var pending: Set<Int> = []
        for id in ids where id >= 0 && !resolvedIds.contains(id) && !priorityIds.contains(id) {
            pending.insert(id)
        }
        guard !pending.isEmpty else { return }
        queuedIds.formUnion(pending)
        scheduleFlush()
    }

    func apply(trackId: Int, data: [Double]?) {
        resolvedIds.insert(trackId)
        queuedIds.remove(trackId)
        priorityIds.remove(trackId)
        if let existing = slots[trackId] {
            existing.data = data
        } else {
            let slot = TrackWaveformSlot()
            slot.data = data
            slots[trackId] = slot
        }
    }

    func invalidate(trackId: Int) {
        resolvedIds.remove(trackId)
        priorityIds.remove(trackId)
        queuedIds.remove(trackId)
        slots[trackId]?.data = nil
    }

    func invalidateAll() {
        flushTask?.cancel()
        flushTask = nil
        resolvedIds.removeAll()
        priorityIds.removeAll()
        queuedIds.removeAll()
        for slot in slots.values {
            slot.data = nil
        }
    }

    private func enqueueLoad(_ id: Int) {
        guard id >= 0, collectionService != nil, !resolvedIds.contains(id), !priorityIds.contains(id) else { return }
        queuedIds.remove(id)
        priorityIds.insert(id)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            self.flushTask = nil
            await self.flush()
        }
    }

    @MainActor
    private func flush() async {
        while !Task.isCancelled {
            guard let collectionService else { return }

            // Serve visible rows first.
            let priority = Array(priorityIds.prefix(Self.chunkSize))
            if !priority.isEmpty {
                for id in priority {
                    priorityIds.remove(id)
                    resolvedIds.insert(id)
                }
                let loaded = await collectionService.loadWaveformBins(ids: priority)
                for id in priority {
                    if let bins = loaded[id] {
                        apply(trackId: id, data: bins)
                    }
                }
                continue
            }

            // Then drain the bulk prewarm queue in chunks, yielding between
            // chunks so the main thread (scrolling, playback) stays responsive.
            let chunk = Array(queuedIds.prefix(Self.chunkSize))
            for id in chunk {
                queuedIds.remove(id)
                resolvedIds.insert(id)
            }
            guard !chunk.isEmpty else { return }
            let loaded = await collectionService.loadWaveformBins(ids: chunk)
            for id in chunk {
                if let bins = loaded[id] {
                    apply(trackId: id, data: bins)
                }
            }
            try? await Task.sleep(nanoseconds: Self.bulkChunkPauseNanos)
        }
    }
}

class WaveformServiceHolder: ObservableObject {
    @Published var service: WaveformProcessingService?
    let status = WaveformStatusModel()
    let waveformStore = WaveformDataStore()
    private var waveformCancellable: AnyCancellable?

    var analyzingCount: Int {
        status.analyzingCount
    }

    func ensure(collectionService: CollectionService) {
        waveformStore.collectionService = collectionService
        guard service == nil else { return }
        collectionService.waveformStatus = status
        service = WaveformProcessingService(collectionService: collectionService, status: status)
        collectionService.syncMissingWaveformCount()
        service?.enqueueAllMissing()
        waveformCancellable = collectionService.waveformDidUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.waveformStore.apply(trackId: update.trackId, data: update.bins)
            }
    }
}

struct WaveformAnalysisStatusBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("analysing")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
            Text(count == 1 ? "track" : "tracks")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Analysing tracks")
        .accessibilityValue("\(count) remaining")
    }
}

struct WaveformAnalysisOverlay: View {
    let collectionService: CollectionService
    let waveformServiceHolder: WaveformServiceHolder

    var body: some View {
        WaveformAnalysisOverlayBadge(status: waveformServiceHolder.status)
            .onAppear {
                waveformServiceHolder.ensure(collectionService: collectionService)
            }
    }
}

private struct WaveformAnalysisOverlayBadge: View {
    @ObservedObject var status: WaveformStatusModel

    var body: some View {
        let missingCount = status.missingCount
        VStack {
            Spacer()
            HStack {
                Spacer()
                if missingCount > 0 {
                    WaveformAnalysisStatusBadge(count: missingCount)
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: missingCount)
        .allowsHitTesting(false)
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
    let waveformData: [Double]
    let playbackProgress: Double
    let isPlayingThisTrack: Bool
    let highDetailWaveform: Bool
    let audioService: AudioService

    static func == (lhs: WaveformListCell, rhs: WaveformListCell) -> Bool {
        guard lhs.track.id == rhs.track.id else { return false }
        guard lhs.waveformData.count == rhs.waveformData.count else { return false }
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
                waveformData: waveformData,
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
    let waveformServiceHolder: WaveformServiceHolder
    let collectionService: CollectionService
    @ObservedObject var slot: TrackWaveformSlot

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

    private var resolvedWaveformData: [Double]? {
        slot.data
    }

    var body: some View {
        columnBodyContent()
    }

    @ViewBuilder
    private func columnBodyContent() -> some View {
        if let data = resolvedWaveformData, !data.isEmpty {
            WaveformListCell(
                track: track,
                waveformData: data,
                playbackProgress: playbackProgress,
                isPlayingThisTrack: isPlayingThisTrack,
                highDetailWaveform: highDetailWaveform,
                audioService: audioService
            )
            .equatable()
        } else if track.waveformStatus == .empty || resolvedWaveformData?.isEmpty == true {
            if emptyWaveformFileExists() {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .onAppear {
                    waveformServiceHolder.ensure(collectionService: collectionService)
                    waveformServiceHolder.service?.analyzeIfMissing(track)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("File missing")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } else if track.waveformStatus == .ready {
            // The waveform exists (status `.ready`) but the slot is still being
            // populated from the database after the row appeared. Render a
            // quiet placeholder instead of an "Analyzing…" spinner so fast
            // scrolling does not flash the label on every newly visible row.
            Color.clear
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Analyzing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Cheap existence check only. Do not call `resolveTrackPathForWaveform` from
    /// the view body — that can recursively search the library on the main thread.
    private func emptyWaveformFileExists() -> Bool {
        let path = track.path
        if path.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: path)
        }
        return true
    }
}


