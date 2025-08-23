import SwiftUI
import Combine

struct AudioPlayerView: View {
    @ObservedObject var audioService: AudioService
    
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
            
            // Progress bar
            VStack(spacing: 5) {
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
}

#Preview {
    AudioPlayerView(audioService: AudioService())
}

