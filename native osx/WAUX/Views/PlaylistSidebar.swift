import SwiftUI

struct PlaylistSidebar: View {
    @ObservedObject var playlistService: PlaylistService
    @Binding var selectedPlaylist: Playlist?
    @State private var showingCreatePlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Library")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    newPlaylistName = ""
                    showingCreatePlaylistAlert = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Create new playlist")
            }
            .padding()
            
            if playlistService.isLoading {
                ProgressView("Loading playlists...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if playlistService.playlists.isEmpty {
                VStack {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text("No playlists")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(playlistService.playlists, id: \.id) { playlist in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack {
                            Text("\(playlist.trackPaths.count) tracks")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if playlist.duration > 0 {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(playlist.formattedDuration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .background(selectedPlaylist?.id == playlist.id ? Color.blue.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        selectedPlaylist = playlist
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .frame(width: 200)
        .background(Color(.controlBackgroundColor))
        .alert("Create New Playlist", isPresented: $showingCreatePlaylistAlert) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                createPlaylist()
            }
        } message: {
            Text("Enter a name for your new playlist")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func createPlaylist() {
        let trimmedName = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errorMessage = "Playlist name cannot be empty"
            showingErrorAlert = true
            return
        }
        
        Task {
            do {
                let newPlaylist = try await playlistService.createPlaylist(name: trimmedName)
                await MainActor.run {
                    selectedPlaylist = newPlaylist
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
}
