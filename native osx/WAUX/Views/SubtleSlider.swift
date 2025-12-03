import SwiftUI

// Custom subtle slider view
struct SubtleSlider: View {
    @Binding var value: Double
    let onChanged: (Double) -> Void
    let currentTime: TimeInterval
    let totalDuration: TimeInterval
    @State private var isHovering = false
    @State private var hoverLocation: CGFloat = 0
    
    init(value: Binding<Double>, onChanged: @escaping (Double) -> Void, currentTime: TimeInterval = 0, totalDuration: TimeInterval = 0) {
        self._value = value
        self.onChanged = onChanged
        self.currentTime = currentTime
        self.totalDuration = totalDuration
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 2)
            
            Rectangle()
                .fill(Color.gray)
                .frame(width: max(0, value * 300), height: 2)
            
            // Small line thumb
            Rectangle()
                .fill(Color.gray)
                .frame(width: 2, height: 12)
                .offset(x: value * 300 - 1)
        }
        .frame(width: 300, height: 20)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gestureValue in
                    let ratio = max(0, min(1, gestureValue.location.x / 300))
                    value = ratio
                    onChanged(ratio)
                }
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .overlay(
            // Hover tooltip
            Group {
                if isHovering {
                    VStack(spacing: 0) {
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .offset(x: -8)
                            
                            Text(formatTime(totalDuration))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .offset(x: 8)
                        }
                        .frame(width: 300)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        
                        // Small triangle pointing up
                        Triangle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .frame(width: 8, height: 4)
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1)
                            .rotationEffect(.degrees(180))
                    }
                    .offset(y: 15)
                }
            }
        )
    }
}

// Custom triangle shape for tooltip pointer
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        SubtleSlider(value: .constant(0.3), onChanged: { _ in }, currentTime: 90, totalDuration: 300)
            .frame(height: 20)
        
        SubtleSlider(value: .constant(0.7), onChanged: { _ in }, currentTime: 210, totalDuration: 300)
            .frame(height: 20)
    }
    .padding()
}
