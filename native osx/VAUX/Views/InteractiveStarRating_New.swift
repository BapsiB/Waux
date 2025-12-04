import SwiftUI

struct InteractiveStarRating_New: View {
    let trackId: Int
    @ObservedObject var metadataManager: TrackMetadataManager
    
    @State private var hoveredStar: Int = 0
    @State private var isHovering: Bool = false
    
    private var track: Track? {
        metadataManager.getTrack(id: trackId)
    }
    
    private var currentRating: Int {
        track?.rating ?? 0
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: starName(for: star))
                    .foregroundColor(starColor(for: star))
                    .font(.caption)
                    .onHover { hovering in
                        if hovering {
                            hoveredStar = star
                            isHovering = true
                        } else {
                            if hoveredStar == star {
                                isHovering = false
                                hoveredStar = 0
                            }
                        }
                    }
                    .onTapGesture {
                        metadataManager.updateRating(for: trackId, rating: star)
                    }
                    .scaleEffect(isHovering && hoveredStar >= star ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isHovering)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
                .onHover { hovering in
                    if !hovering {
                        isHovering = false
                        hoveredStar = 0
                    }
                }
        )
    }
    
    private func starName(for star: Int) -> String {
        if isHovering && hoveredStar >= star {
            return "star.fill"
        } else if star <= currentRating {
            return "star.fill"
        } else {
            return "star"
        }
    }
    
    private func starColor(for star: Int) -> Color {
        if isHovering && hoveredStar >= star {
            return .orange
        } else if star <= currentRating {
            return .yellow
        } else {
            return .gray
        }
    }
}
