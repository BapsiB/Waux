import SwiftUI

struct CompactAudioPlayerView: View {
    @ObservedObject var audioService: AudioService
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 1/4: Control buttons
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
                .frame(width: geometry.size.width * 0.25)
                
                // 1/2: Title with playback slider under
                VStack(alignment: .center, spacing: 4) {
                    if let track = audioService.currentTrack {
                        VStack(alignment: .center, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                            
                            if !track.artist.isEmpty && track.artist != "Unknown" {
                                Text(track.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Text("No track")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Timeline with subtle slider
                    VStack(spacing: 4) {
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
                        .frame(maxWidth: .infinity)
                        
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
                    }
                }
                .frame(width: geometry.size.width * 0.5)
                
                // 1/4: Volume control
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { Double(audioService.volume) },
                        set: { audioService.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(maxWidth: .infinity)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(width: geometry.size.width * 0.25)
                
                // Loading indicator (overlay)
                if audioService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.6)
                        .position(x: geometry.size.width - 20, y: geometry.size.height / 2)
                }
            }
        }
        .frame(height: 50)
    }
}



#Preview {
    CompactAudioPlayerView(audioService: AudioService())
}
