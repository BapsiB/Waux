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
                        Task {
                            await audioService.playPreviousTrack()
                        }
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .frame(minWidth: 30)
                            .contentShape(Rectangle())
                    }
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .buttonStyle(.plain)

                    
                    Button(action: {
                        audioService.togglePlayPause()
                    }) {
                        Image(systemName: audioService.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .frame(minWidth: 30)
                            .contentShape(Rectangle())
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
                            .frame(minWidth: 30)
                            .contentShape(Rectangle())
                    }
                    .disabled(audioService.currentTrack == nil || audioService.isLoading)
                    .buttonStyle(.plain)

                }
                .frame(width: geometry.size.width * 0.25)
                .frame(maxHeight: .infinity)
                
                // 1/2: Album artwork, title, and playback slider
                CentralAudioPlayerControls(audioService: audioService, collectionService: collectionService)
                .frame(width: geometry.size.width * 0.6)
                .frame(maxHeight: .infinity)
                
                // 1/4: Volume control
                HStack(spacing: 8) {
                    
                    CustomVolumeSlider(
                        value: Binding(
                            get: { Double(audioService.volume) },
                            set: { audioService.setVolume(Float($0)) }
                        )
                    )
                    .frame(maxWidth: .infinity)
                
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

struct CustomVolumeSlider: View {
    @Binding var value: Double
    @State private var isHovered = false
    
    private func valueFromSliderLocation(x: CGFloat, width: CGFloat) -> Double {
        let inset: CGFloat = 8
        let trackWidth = max(width - 2 * inset, 1)
        let clamped = max(0, min(1, (x - inset) / trackWidth))
        return Double(clamped)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                
                // Filled track (matches thumb inset so click position aligns with fill)
                Rectangle()
                    .fill(AppStyle.mainColor)
                    .frame(width: 8 + (w - 16) * CGFloat(value), height: 2)
                
                // Custom thumb (visual only; whole bar handles drag / click)
                Circle()
                    .fill(AppStyle.mainColor)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isHovered ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                    .position(
                        x: 8 + (w - 16) * CGFloat(value),
                        y: geometry.size.height / 2
                    )
                    .animation(.easeInOut(duration: 0.2))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = valueFromSliderLocation(x: gesture.location.x, width: w)
                    }
            )
        }
    }
}
