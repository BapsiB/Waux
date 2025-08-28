import SwiftUI
import Combine

struct AudioPlayerView: View {
    @ObservedObject var audioService: AudioService
    
    // Sample track for testing waveform functionality
    private let sampleTrack = Track(
        title: "Sample Audio Track",
        artist: "Sample Artist",
        album: "Sample Album",
        path: "/System/Library/Sounds/Glass.aiff", // System sound for testing
        isUrl: false,
        duration: 3000, // 3 seconds
        timeMarkers: [
            TimeMarker(time: 500, label: "Intro", color: .green),
            TimeMarker(time: 1500, label: "Middle", color: .orange),
            TimeMarker(time: 2500, label: "End", color: .red)
        ],
        waveformData: Array(repeating: Double.random(in: 0.1...1.0), count: 100) // Random waveform data
    )
    
    var body: some View {
        VStack(spacing: 20) {
            // Track info
            if let track = audioService.currentTrack {
                VStack(spacing: 10) {
                    Text(track.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    if !track.artist.isEmpty && track.artist != "Unknown" {
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 5)
                
                // Progress bar - moved under track title
                VStack(spacing: 5) {
                    // Seek bar
                    SubtleSlider(
                        value: Binding(
                            get: { audioService.duration > 0 ? audioService.currentTime / audioService.duration : 0 },
                            set: { ratio in
                                audioService.seekToRatio(ratio)
                            }
                        ),
                        onChanged: { ratio in
                            audioService.seekToRatio(ratio)
                        }
                    )
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    
                    HStack {
                        Text(audioService.formatTime(audioService.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(audioService.formatTime(audioService.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            } else {
                Text("No track loaded")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            }
            
            // Error message
            if let errorMessage = audioService.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // Waveform view
            if let track = audioService.currentTrack, let waveformData = track.waveformData {
                VStack(spacing: 8) {
                    Text("Waveform (click to seek)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    WaveformView(
                        waveformData: waveformData,
                        progress: audioService.duration > 0 ? audioService.currentTime / audioService.duration : 0,
                        markers: track.timeMarkers,
                        durationMs: track.duration,
                        onTap: { ratio in
                            handleWaveformTap(ratio: ratio)
                        }
                    )
                    .frame(height: 80)
                    .padding(.horizontal)
                }
            } else {
                // Show sample waveform when no track is loaded
                VStack(spacing: 8) {
                    Text("Sample Waveform (click to load and seek)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    WaveformView(
                        waveformData: sampleTrack.waveformData ?? [],
                        progress: 0.0,
                        markers: sampleTrack.timeMarkers,
                        durationMs: sampleTrack.duration,
                        onTap: { ratio in
                            handleSampleWaveformTap(ratio: ratio)
                        }
                    )
                    .frame(height: 80)
                    .padding(.horizontal)
                }
            }
            
            // Loading indicator
            if audioService.isLoading {
                ProgressView("Loading...")
                    .progressViewStyle(CircularProgressViewStyle())
            }
            
            // Playback controls
            HStack(spacing: 30) {
                Button(action: {
                    // TODO: Implement previous track
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(audioService.currentTrack == nil || audioService.isLoading)
                
                Button(action: {
                    audioService.togglePlayPause()
                }) {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.blue))
                        .foregroundColor(.white)
                }
                .disabled(audioService.currentTrack == nil || audioService.isLoading)
                
                Button(action: {
                    // TODO: Implement next track
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(audioService.currentTrack == nil || audioService.isLoading)
            }
            
            // Volume control
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.secondary)
                
                Slider(value: Binding(
                    get: { Double(audioService.volume) },
                    set: { audioService.setVolume(Float($0)) }
                ), in: 0...1)
                
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
        .frame(minWidth: 300, minHeight: 200)
    }
    
    // Handle waveform tap for loaded tracks
    private func handleWaveformTap(ratio: Double) {
        guard let track = audioService.currentTrack else { return }
        
        // Seek to the clicked position
        audioService.seekToRatio(ratio)
        
        // If not playing, start playing
        if !audioService.isPlaying {
            audioService.play()
        }
    }
    
    // Handle waveform tap for sample track (load and seek)
    private func handleSampleWaveformTap(ratio: Double) {
        Task {
            // Load the sample track
            await audioService.loadTrack(sampleTrack)
            
            // Seek to the clicked position
            audioService.seekToRatio(ratio)
            
            // Start playing
            audioService.play()
        }
    }
}

// New compact header-based audio player
struct HeaderAudioPlayerView: View {
    @ObservedObject var audioService: AudioService
    
    // Sample track for testing waveform functionality
    private let sampleTrack = Track(
        title: "Sample Audio Track",
        artist: "Sample Artist",
        album: "Sample Album",
        path: "/System/Library/Sounds/Glass.aiff", // System sound for testing
        isUrl: false,
        duration: 3000, // 3 seconds
        timeMarkers: [
            TimeMarker(time: 500, label: "Intro", color: .green),
            TimeMarker(time: 1500, label: "Middle", color: .orange),
            TimeMarker(time: 2500, label: "End", color: .red)
        ],
        waveformData: Array(repeating: Double.random(in: 0.1...1.0), count: 100) // Random waveform data
    )
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                // Playback controls
                HStack(spacing: 12) {
                    Button(action: {
                        // TODO: Implement previous track
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        audioService.togglePlayPause()
                    }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        // TODO: Implement next track
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .buttonStyle(.plain)
                }
                
                // Track info
                if let track = audioService.currentTrack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        
                        if !track.artist.isEmpty && track.artist != "Unknown" {
                            Text(track.artist)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                } else {
                    Text("No track")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 200, alignment: .leading)
                }
                
                // Timeline
                VStack(spacing: 4) {
                    // Seek bar
                    Slider(
                        value: Binding(
                            get: { audioService.duration > 0 ? audioService.currentTime / audioService.duration : 0 },
                            set: { ratio in
                                audioService.seekToRatio(ratio)
                            }
                        ),
                        in: 0...1
                    )
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .frame(width: 300)
                    
                    HStack {
                        Text(audioService.formatTime(audioService.currentTime))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(audioService.formatTime(audioService.duration))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    .frame(width: 300)
                }
                
                // Volume control
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { Double(audioService.volume) },
                        set: { audioService.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(width: 80)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                // Loading indicator
                if audioService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.6)
                }
            }
            
            // Waveform view
            if let track = audioService.currentTrack, let waveformData = track.waveformData {
                WaveformView(
                    waveformData: waveformData,
                    progress: audioService.duration > 0 ? audioService.currentTime / audioService.duration : 0,
                    markers: track.timeMarkers,
                    durationMs: track.duration,
                    onTap: { ratio in
                        handleWaveformTap(ratio: ratio)
                    }
                )
                .frame(height: 40)
                .padding(.horizontal, 16)
            } else {
                // Show sample waveform when no track is loaded
                WaveformView(
                    waveformData: sampleTrack.waveformData ?? [],
                    progress: 0.0,
                    markers: sampleTrack.timeMarkers,
                    durationMs: sampleTrack.duration,
                    onTap: { ratio in
                        handleSampleWaveformTap(ratio: ratio)
                    }
                )
                .frame(height: 40)
                .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .border(Color(.separatorColor), width: 0.5)
    }
    
    // Handle waveform tap for loaded tracks
    private func handleWaveformTap(ratio: Double) {
        guard let track = audioService.currentTrack else { return }
        
        // Seek to the clicked position
        audioService.seekToRatio(ratio)
        
        // If not playing, start playing
        if !audioService.isPlaying {
            audioService.play()
        }
    }
    
    // Handle waveform tap for sample track (load and seek)
    private func handleSampleWaveformTap(ratio: Double) {
        Task {
            // Load the sample track
            await audioService.loadTrack(sampleTrack)
            
            // Seek to the clicked position
            audioService.seekToRatio(ratio)
            
            // Start playing
            audioService.play()
        }
    }
}

// Custom subtle slider view
struct SubtleSlider: View {
    @Binding var value: Double
    let onChanged: (Double) -> Void
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 2)
            
            Rectangle()
                .fill(Color.gray)
                .frame(width: max(0, value * 300), height: 2)
            
            // Small line thumb
            Rectangle()
                .fill(Color.gray)
                .frame(width: 2, height: 12)
                .offset(x: value * 300 - 1)
        }
        .frame(width: 300, height: 20)
        .contentShape(Rectangle())
        .onTapGesture { location in
            let ratio = max(0, min(1, location.x / 300))
            value = ratio
            onChanged(ratio)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gestureValue in
                    let ratio = max(0, min(1, gestureValue.location.x / 300))
                    value = ratio
                    onChanged(ratio)
                }
        )
    }
}

#Preview {
    VStack {
        HeaderAudioPlayerView(audioService: AudioService())
        AudioPlayerView(audioService: AudioService())
    }
}

