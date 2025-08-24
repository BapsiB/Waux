import SwiftUI

struct DatabaseRepairView: View {
    let collectionService: CollectionService
    @Binding var corruptedTracks: [(id: Int, title: String, issues: [String])]
    @Binding var isScanning: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Database Repair Tool")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("This tool helps identify and fix tracks with corrupted metadata that prevent them from loading properly.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if isScanning {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Scanning database for corrupted tracks...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if corruptedTracks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        
                        Text("No corrupted tracks found!")
                            .font(.headline)
                        
                        Text("All tracks in your database appear to have valid metadata.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Found \(corruptedTracks.count) corrupted tracks")
                                .font(.headline)
                        }
                        
                        Text("These tracks have metadata encoding issues that prevent them from loading properly.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(corruptedTracks, id: \.id) { track in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(track.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        ForEach(track.issues, id: \.self) { issue in
                                            Text("• \(issue)")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                        
                                        Button("Fix This Track") {
                                            Task {
                                                await fixTrack(track.id)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .font(.caption)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(6)
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                        
                        HStack {
                            Button("Fix All Corrupted Tracks") {
                                Task {
                                    await fixAllTracks()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(corruptedTracks.isEmpty)
                            
                            Button("Auto-Fix All Issues") {
                                Task {
                                    await autoFixAllIssues()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                }
                
                Spacer()
                
                HStack {
                    Button("Scan Again") {
                        Task {
                            await scanForCorruptedTracks()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(minWidth: 500, minHeight: 400)
        }
        .onAppear {
            Task {
                await scanForCorruptedTracks()
            }
        }
    }
    
    private func scanForCorruptedTracks() async {
        await MainActor.run {
            isScanning = true
        }
        
        do {
            let corrupted = try await collectionService.scanForCorruptedTracks()
            await MainActor.run {
                corruptedTracks = corrupted
                isScanning = false
            }
        } catch {
            print("Error scanning for corrupted tracks: \(error)")
            await MainActor.run {
                isScanning = false
            }
        }
    }
    
    private func fixTrack(_ trackId: Int) async {
        do {
            try await collectionService.fixCorruptedTrackMetadata(trackId: trackId)
            // Remove the fixed track from the list
            await MainActor.run {
                corruptedTracks.removeAll { $0.id == trackId }
            }
        } catch {
            print("Error fixing track \(trackId): \(error)")
        }
    }
    
    private func fixAllTracks() async {
        let tracksToFix = corruptedTracks
        for track in tracksToFix {
            await fixTrack(track.id)
        }
    }
    
    private func autoFixAllIssues() async {
        do {
            try await collectionService.autoFixCorruptedMetadata()
            // Refresh the corrupted tracks list
            await scanForCorruptedTracks()
        } catch {
            print("Error during auto-fix: \(error)")
        }
    }
}

#Preview {
    DatabaseRepairView(
        collectionService: CollectionService(),
        corruptedTracks: .constant([
            (id: 1, title: "Sample Track - Artist", issues: ["Corrupted generalTags JSON"]),
            (id: 2, title: "Another Track - Artist", issues: ["Invalid timeMarkers encoding"])
        ]),
        isScanning: .constant(false)
    )
}
