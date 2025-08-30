import SwiftUI

struct CompactAudioPlayerView: View {
    @ObservedObject var audioService: AudioService
    let collectionService: CollectionService?
    
    init(audioService: AudioService, collectionService: CollectionService? = nil) {
        self.audioService = audioService
        self.collectionService = collectionService
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 0) {
                // Use alignment to center all elements vertically
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
                .frame(maxHeight: .infinity)
                
                // 1/2: Album artwork, title, and playback slider
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        // Album artwork
                        if let track = audioService.currentTrack {
                            AlbumArtworkView(track: track, size: CGSize(width: 40, height: 40), collectionService: collectionService)
                        } else {
                            // Placeholder for no track
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                        }
                        
                        // Title and artist
                        VStack(alignment: .center, spacing: 2) {
                            if let track = audioService.currentTrack {
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
                            } else {
                                Text("No track")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        Spacer()
                    }.offset(x: 64)
                    
                    // Timeline with subtle slider
                    VStack(spacing: 0) {
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
                    }
                }
                .frame(width: geometry.size.width * 0.6)
                .frame(maxHeight: .infinity)
                
                // 1/4: Volume control
                HStack(spacing: 8) {
                    
                    Slider(value: Binding(
                        get: { Double(audioService.volume) },
                        set: { audioService.setVolume(Float($0)) }
                    ), in: 0...1)
                    .frame(maxWidth: .infinity)
                    .accentColor(.gray)
                
                }
                .frame(width: geometry.size.width * 0.15)
                .frame(maxHeight: .infinity)
                // .padding(.bottom, 34)
                .clipped()
                .scaleEffect(x: 0.5, y: 0.5)
                
                // Loading indicator (overlay)
                if audioService.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.6)
                        .position(x: geometry.size.width - 20, y: geometry.size.height / 2)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .offset(y: -18)
    }
}



#Preview {
    CompactAudioPlayerView(audioService: AudioService())
}
