import SwiftUI

struct InteractiveStarRating: View {
    let track: Track
    let onRatingChanged: (Int) -> Void
    
    @State private var hoveredStar: Int = 0
    @State private var isHovering: Bool = false
    
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
                        onRatingChanged(star)
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
        } else if star <= track.rating {
            return "star.fill"
        } else {
            return "star"
        }
    }
    
    private func starColor(for star: Int) -> Color {
        if isHovering && hoveredStar >= star {
            return .orange
        } else if star <= track.rating {
            return .yellow
        } else {
            return .gray
        }
    }
}

#Preview {
    InteractiveStarRating(
        track: Track(
            title: "Sample Track",
            artist: "Sample Artist",
            album: "Sample Album",
            path: "/path/to/track.mp3",
            isUrl: false,
            duration: 180000,
            rating: 3
        )
    ) { newRating in
        print("Rating changed to: \(newRating)")
    }
}
