import SwiftUI

struct SnackbarView: View {
    let message: String
    let onDismiss: () -> Void
    @State private var isVisible = false
    
    var body: some View {
        HStack {
            Text(message)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .shadow(radius: 4)
        .offset(y: isVisible ? 0 : 100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = true
            }
            
            // Auto-dismiss after 4 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                dismissWithAnimation()
            }
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeIn(duration: 0.3)) {
            isVisible = false
        }
        
        // Call onDismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()
        
        VStack {
            Spacer()
            
            SnackbarView(message: "3 tracks were already in My Playlist") {
                print("Snackbar dismissed")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
}