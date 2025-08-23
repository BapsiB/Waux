import SwiftUI

struct AudioPlayerView: View {
    @ObservedObject var audioService: AudioService
    
    var body: some View {
        VStack(spacing: 20) {
            // Track info
            if let track = audioService.currentTrack {
                VStack(spacing: 10) {
                    Text(track.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    
                    if let album = track.album {
                        Text(album)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 10)
            }
            
            // Progress bar
            VStack(spacing: 5) {
                ProgressView(value: audioService.duration > 0 ? audioService.currentTime / audioService.duration : 0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .scaleEffect(y: 2)
                
                HStack {
                    Text(formatTime(audioService.currentTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTime(audioService.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            
            // Playback controls
            HStack(spacing: 30) {
                Button(action: {
                    // TODO: Implement previous track
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .disabled(audioService.currentTrack == nil)
                
                Button(action: {
                    if audioService.isPlaying { audioService.pause() } else { audioService.play() }
                }) {
                    Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(Color.blue))
                        .foregroundColor(.white)
                }.disabled(audioService.currentTrack == nil)
                
                Button(action: {
                    // TODO: Implement next track
                }) {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .disabled(audioService.currentTrack == nil)
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
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    AudioPlayerView(audioService: AudioService())
}

