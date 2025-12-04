import SwiftUI

struct AlbumArtworkView: View {
    let track: Track
    let size: CGSize
    let collectionService: CollectionService?
    
    @State private var artworkImage: NSImage?
    @State private var isLoading = false
    
    init(track: Track, size: CGSize = CGSize(width: 60, height: 60), collectionService: CollectionService? = nil) {
        self.track = track
        self.size = size
        self.collectionService = collectionService
    }
    
    var body: some View {
        Group {
            if let image = artworkImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(6)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                    .frame(width: size.width, height: size.height)
            } else {
                // Default artwork
                defaultArtworkView
            }
        }
        .onAppear {
            loadArtwork()
        }
        .onChange(of: track.id) { _ in
            loadArtwork()
        }
    }
    
    private var defaultArtworkView: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.8)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Music note icon
            Image(systemName: "music.note")
                .font(.system(size: size.width * 0.3))
                .foregroundColor(.white)
        }
        .frame(width: size.width, height: size.height)
        .cornerRadius(6)
    }
    
    private func loadArtwork() {
        // Don't try to load artwork for URL tracks
        guard !track.isUrl else {
            artworkImage = nil
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let artworkData = await AlbumArtworkService.shared.extractAlbumArtwork(from: track, collectionService: collectionService)
                
                await MainActor.run {
                    if let artworkData = artworkData,
                       let image = NSImage(data: artworkData) {
                        self.artworkImage = image
                    } else {
                        self.artworkImage = nil
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.artworkImage = nil
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AlbumArtworkView(
            track: Track(
                title: "Sample Track",
                artist: "Sample Artist",
                album: "Sample Album",
                path: "",
                isUrl: false,
                duration: 180000
            ),
            size: CGSize(width: 80, height: 80)
        )
        
        AlbumArtworkView(
            track: Track(
                title: "Another Track",
                artist: "Another Artist",
                album: "Another Album",
                path: "",
                isUrl: false,
                duration: 240000
            ),
            size: CGSize(width: 60, height: 60)
        )
    }
    .padding()
}
