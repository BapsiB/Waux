import Foundation
import AVFoundation
import Combine

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
    
    // Callbacks to get the next/previous track for auto-play and manual navigation
    var getNextTrack: (() -> Track?)?
    var getPreviousTrack: (() -> Track?)?
    
    override init() {
        super.init()
        setupAudioSession()
        setupTimer()
        loadVolumeFromPreferences()
    }
    
    deinit {
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        guard let player = audioPlayer else { return }
        currentTime = player.currentTime
        duration = player.duration
    }
    
    private func loadVolumeFromPreferences() {
        volume = preferenceService.volume
    }
    
    func loadTrack(_ track: Track) async {
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
            
            print("Audio player created successfully")
            print("Duration: \(audioPlayer?.duration ?? 0) seconds")
            print("Format: \(audioPlayer?.format.description ?? "Unknown")")
            
            await MainActor.run {
                currentTrack = track
                duration = track.isUrl ? audioPlayer?.duration ?? 0 : TimeInterval(track.duration / 1000)
                currentTime = 0
                isPlaying = false
                isLoading = false
            }
            
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
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        player.play()
        isPlaying = true
    }
    
    func pause() {
        guard let player = audioPlayer else { return }
        player.pause()
        isPlaying = false
    }
    
    func stop() {
        print("stop()")
        guard let player = audioPlayer else { return }
        player.stop()
        player.currentTime = 0
        isPlaying = false
        currentTime = 0
    }
    
    func seek(to timeS: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = timeS
        currentTime = timeS
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
        Task {
            await loadTrack(nextTrack)
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
        await loadTrack(nextTrack)
        play()
    }
    
    /// Plays the previous track manually (for previous button)
    func playPreviousTrack() async {
        guard let previousTrack = getPreviousTrack?() else {
            print("No previous track available")
            return
        }
        
        print("Manually playing previous track: \(previousTrack.title)")
        await loadTrack(previousTrack)
        play()
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
            self.currentTime = 0
            print("audioPlayerDidFinishPlaying")
            
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
            self.errorMessage = error?.localizedDescription ?? "Unknown error"
        }
    }
}

