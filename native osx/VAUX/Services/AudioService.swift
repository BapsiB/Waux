import Foundation
import AVFoundation
import Combine
#if os(macOS)
import AppKit
import MediaPlayer
#endif

class AudioService: NSObject, ObservableObject {
    @Published var currentTrack: Track?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.8
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let preferenceService = PreferenceService.shared
    
    // Timer optimization
    private var isIdle = true
    private let idleUpdateInterval: TimeInterval = 1.0  // 1 second when idle
    private let activeUpdateInterval: TimeInterval = 0.1 // 0.1 seconds when playing
    
    // Callbacks to get the next/previous track for auto-play and manual navigation
    var getNextTrack: (() -> Track?)?
    var getPreviousTrack: (() -> Track?)?
    
    #if os(macOS)
    /// Refreshes Now Playing on a ~1s cadence while audio is running so macOS keeps routing media keys here.
    private var nowPlayingHeartbeatTick: Int = 0
    private var appBecameActiveObserver: NSObjectProtocol?
    #endif
    
    override init() {
        super.init()
        setupAudioSession()
        setupTimer()
        loadVolumeFromPreferences()
        #if os(macOS)
        setupRemoteTransportControls()
        #endif
    }
    
    deinit {
        #if os(macOS)
        teardownRemoteTransportControls()
        #endif
        timer?.invalidate()
        audioPlayer?.stop()
    }
    
    private func setupAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
        #else
        // AVAudioSession is unavailable on macOS. No setup needed.
        #endif
    }
    
    private func setupTimer() {
        updateTimerInterval()
    }
    
    private func updateTimerInterval() {
        timer?.invalidate()
        
        let interval = isIdle ? idleUpdateInterval : activeUpdateInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        guard let player = audioPlayer else { return }
        
        let newCurrentTime = player.currentTime
        let newDuration = player.duration
        
        // Only update @Published properties if values actually changed
        // This prevents unnecessary SwiftUI view updates
        if abs(newCurrentTime - currentTime) > 0.01 { // 10ms threshold
            currentTime = newCurrentTime
        }
        
        if abs(newDuration - duration) > 0.01 { // 10ms threshold
            duration = newDuration
        }
        
        #if os(macOS)
        if isPlaying {
            nowPlayingHeartbeatTick += 1
            if nowPlayingHeartbeatTick >= 10 {
                nowPlayingHeartbeatTick = 0
                syncNowPlayingInfo()
            }
        } else {
            nowPlayingHeartbeatTick = 0
        }
        #endif
    }
    
    private func loadVolumeFromPreferences() {
        volume = preferenceService.volume
    }
    
    func loadTrack(_ track: Track) async -> AVAudioPlayer? {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let url: URL
            if track.isUrl {
                guard let trackUrl = URL(string: track.path) else {
                    throw AudioServiceError.invalidUrl
                }
                url = trackUrl
                print("Loading URL track: \(url)")
            } else {
                url = URL(fileURLWithPath: track.path)
                print("Loading local track: \(url)")
                
                // Check if file exists
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: track.path) else {
                    throw AudioServiceError.fileNotFound
                }
                
                // Get file size
                let attributes = try fileManager.attributesOfItem(atPath: track.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("File size: \(fileSize) bytes")
                
                if fileSize == 0 {
                    throw AudioServiceError.fileNotFound
                }
            }
            
            // Create audio player
            print("Creating AVAudioPlayer for: \(url)")
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.volume = volume
            
            // Set currentTime to 0 to stabilize duration
            audioPlayer?.currentTime = 0
            
            print("Audio player created successfully")
            print("Duration: \(audioPlayer?.duration ?? 0) seconds")
            print("Format: \(audioPlayer?.format.description ?? "Unknown")")
            
            await MainActor.run {
                currentTrack = track
                // Always use the actual audio player duration, not the stored track duration
                let playerDuration = audioPlayer?.duration ?? 0
                duration = playerDuration
                currentTime = 0
                isPlaying = false
                isIdle = true
                isLoading = false
                updateTimerInterval()
                print("🔍 [AudioService] loadTrack: player.duration=\(String(format: "%.1f", playerDuration))s, set duration=\(String(format: "%.1f", duration))s")
                syncNowPlayingInfo()
            }
            
            return audioPlayer
            
        } catch {
            print("Error loading track: \(error)")
            print("Error domain: \((error as NSError).domain)")
            print("Error code: \((error as NSError).code)")
            print("Error description: \((error as NSError).localizedDescription)")
            print("Error user info: \((error as NSError).userInfo)")
            
            await MainActor.run {
                let errorDescription: String
                if let audioError = error as? AudioServiceError {
                    errorDescription = audioError.errorDescription ?? "Unknown error"
                } else {
                    errorDescription = "Failed to load track: \(error.localizedDescription)"
                }
                errorMessage = errorDescription
                isLoading = false
            }
            return nil
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        player.play()
        isPlaying = true
        isIdle = false
        updateTimerInterval()
        syncNowPlayingInfo()
    }
    
    func pause() {
        guard let player = audioPlayer else { return }
        player.pause()
        isPlaying = false
        isIdle = true
        updateTimerInterval()
        syncNowPlayingInfo()
    }
    
    func stop() {
        print("stop()")
        guard let player = audioPlayer else { return }
        player.stop()
        player.currentTime = 0
        isPlaying = false
        isIdle = true
        currentTime = 0
        updateTimerInterval()
        syncNowPlayingInfo()
    }
    
    func seek(to timeS: TimeInterval) {
        guard let player = audioPlayer else { return }
        let durationBefore = player.duration
        player.currentTime = timeS
        let durationAfter = player.duration  // This is the correct duration
        currentTime = timeS
        
        // Update our stored duration with the correct value (after seeking)
        if abs(durationAfter - duration) > 0.01 {
            duration = durationAfter
        }
        
        print("🔍 [AudioService] seek: requested=\(String(format: "%.1f", timeS))s, durationBefore=\(String(format: "%.1f", durationBefore))s, durationAfter=\(String(format: "%.1f", durationAfter))s, currentTime=\(String(format: "%.1f", currentTime))s")
        syncNowPlayingInfo()
    }
    
    func seekToRatio(_ ratio: Double) {
        guard audioPlayer != nil, duration > 0 else { return }
        let targetTime = duration * ratio
        seek(to: targetTime)
    }
    
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        audioPlayer?.volume = volume
        preferenceService.volume = volume
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    #if os(macOS)
    /// Hardware media keys (F7–F9 / Touch Bar) and Control Center route through `MPRemoteCommandCenter`
    /// when Now Playing info is published.
    private func setupRemoteTransportControls() {
        let center = MPRemoteCommandCenter.shared()
        
        center.togglePlayPauseCommand.isEnabled = true
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentTrack != nil, !self.isLoading else { return }
                self.togglePlayPause()
            }
            return .success
        }
        
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentTrack != nil, !self.isLoading else { return }
                if !self.isPlaying { self.play() }
            }
            return .success
        }
        
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentTrack != nil else { return }
                if self.isPlaying { self.pause() }
            }
            return .success
        }
        
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentTrack != nil, !self.isLoading else { return }
                await self.playNextTrack()
            }
            return .success
        }
        
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.currentTrack != nil, !self.isLoading else { return }
                await self.playPreviousTrack()
            }
            return .success
        }
        
        syncNowPlayingInfo()
        appBecameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncNowPlayingInfo()
        }
    }
    
    private func teardownRemoteTransportControls() {
        if let appBecameActiveObserver {
            NotificationCenter.default.removeObserver(appBecameActiveObserver)
        }
        appBecameActiveObserver = nil
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.nextTrackCommand.removeTarget(nil)
        center.previousTrackCommand.removeTarget(nil)
        let npc = MPNowPlayingInfoCenter.default()
        npc.playbackState = .stopped
        npc.nowPlayingInfo = nil
    }
    #endif
    
    private func syncNowPlayingInfo() {
        #if os(macOS)
        let npc = MPNowPlayingInfoCenter.default()
        guard let track = currentTrack else {
            npc.playbackState = .stopped
            npc.nowPlayingInfo = nil
            return
        }
        npc.nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: 1),
        ]
        npc.playbackState = isPlaying ? .playing : .paused
        #endif
    }
    
    // MARK: - Auto-play functionality
    
    /// Sets the callback function to get the next track for auto-play
    func setNextTrackCallback(_ callback: @escaping () -> Track?) {
        getNextTrack = callback
    }
    
    /// Sets the callback function to get the previous track
    func setPreviousTrackCallback(_ callback: @escaping () -> Track?) {
        getPreviousTrack = callback
    }
    
    /// Automatically plays the next track if available
    private func playNextTrack() {
        guard let nextTrack = getNextTrack?() else {
            print("No next track available for auto-play")
            return
        }
        
        print("Auto-playing next track: \(nextTrack.title)")
        // `play()` must run on the main actor: `updateTimerInterval()` uses
        // `Timer.scheduledTimer`, which is tied to the current run loop. A plain
        // `Task { }` continuation after `await loadTrack` can run on a background
        // executor whose run loop never fires the timer, so `currentTime` never updates.
        Task { @MainActor in
            _ = await loadTrack(nextTrack)
            play()
        }
    }
    
    /// Plays the next track manually (for next button)
    func playNextTrack() async {
        guard let nextTrack = getNextTrack?() else {
            print("No next track available")
            return
        }
        
        print("Manually playing next track: \(nextTrack.title)")
        _ = await loadTrack(nextTrack)
        await MainActor.run {
            play()
        }
    }
    
    /// Plays the previous track manually (for previous button)
    func playPreviousTrack() async {
        guard let previousTrack = getPreviousTrack?() else {
            print("No previous track available")
            return
        }
        
        print("Manually playing previous track: \(previousTrack.title)")
        _ = await loadTrack(previousTrack)
        await MainActor.run {
            play()
        }
    }
}

enum AudioServiceError: Error, LocalizedError {
    case invalidUrl
    case fileNotFound
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Invalid URL"
        case .fileNotFound:
            return "File not found"
        case .unsupportedFormat:
            return "Unsupported audio format"
        }
    }
}

extension AudioService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isIdle = true
            self.currentTime = 0
            self.updateTimerInterval()
            print("audioPlayerDidFinishPlaying")
            self.syncNowPlayingInfo()
            
            // Auto-play next track if available
            if flag {
                self.playNextTrack()
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(error?.localizedDescription ?? "Unknown error")")
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isIdle = true
            self.updateTimerInterval()
            self.errorMessage = error?.localizedDescription ?? "Unknown error"
        }
    }
    
    /// Get the current audio player duration (for immediate access after loading)
    var currentAudioPlayerDuration: TimeInterval {
        let duration = audioPlayer?.duration ?? 0
        print("🔍 [AudioService] currentAudioPlayerDuration: \(String(format: "%.1f", duration))s")
        return duration
    }
}

