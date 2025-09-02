import SwiftUI

struct AudioPlayerHeader: View {
    @ObservedObject var audioService: AudioService
    
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            
            // Audio player controls (only show when track is loaded)
            if audioService.currentTrack != nil {
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await audioService.playPreviousTrack()
                        }
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
                        Task {
                            await audioService.playNextTrack()
                        }
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
                }
                
                // Timeline
                VStack(spacing: 4) {
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
                    .frame(width: 200)
                    
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
                    .frame(width: 200)
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
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
}
