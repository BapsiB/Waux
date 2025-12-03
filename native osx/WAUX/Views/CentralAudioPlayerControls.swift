import SwiftUI

struct CentralAudioPlayerControls: View {
    @ObservedObject var audioService: AudioService
    let collectionService: CollectionService?
    
    var body: some View {
        HStack(spacing: 0) {
            // Album artwork on the left
            if let track = audioService.currentTrack {
                AlbumArtworkView(track: track, size: CGSize(width: 50, height: 50), collectionService: collectionService)
                    .padding(.leading, 45)
            } else {
                // Placeholder for no track
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .padding(.leading, 50)
            }
            
            // Title and position bar centered as one component
            VStack(spacing: 0) {
                // Title and artist centered
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
                .frame(maxWidth: .infinity)
                
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
                        },
                        currentTime: audioService.currentTime,
                        totalDuration: audioService.duration
                    )
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .frame(maxWidth: .infinity)
                    
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 10) // Add a little spacing between artwork and content
        }
    }
}

#Preview {
    CentralAudioPlayerControls(audioService: AudioService(), collectionService: nil)
}
