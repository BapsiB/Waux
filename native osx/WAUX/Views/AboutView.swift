import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // App Icon
            Image(systemName: "music.note")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            // App Name and Version
            VStack(spacing: 8) {
                Text("WAUX")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Version 1.0.0")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            
            // Description
            Text("A native macOS audio collection manager for organizing and playing your music library.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            
            // Developer Info
            VStack(spacing: 4) {
                Text("Developed by")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Baptiste Bohelay")
                    .font(.headline)
                    .fontWeight(.medium)
            }
            
            // Copyright
            Text("© 2025 Baptiste Bohelay. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Close Button
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    AboutView()
}


