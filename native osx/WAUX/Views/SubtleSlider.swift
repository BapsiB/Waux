import SwiftUI

// Custom subtle slider view
struct SubtleSlider: View {
    @Binding var value: Double
    let onChanged: (Double) -> Void
    
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
        .onTapGesture { location in
            let ratio = max(0, min(1, location.x / 300))
            value = ratio
            onChanged(ratio)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gestureValue in
                    let ratio = max(0, min(1, gestureValue.location.x / 300))
                    value = ratio
                    onChanged(ratio)
                }
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        SubtleSlider(value: .constant(0.3)) { _ in }
            .frame(height: 20)
        
        SubtleSlider(value: .constant(0.7)) { _ in }
            .frame(height: 20)
    }
    .padding()
}
