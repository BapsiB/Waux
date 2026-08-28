import SwiftUI

struct PlaylistView: View {
    @ObservedObject var playlistService: PlaylistService
    @State private var showingCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylist: Playlist?
    @State private var showingRenamePlaylist = false
    @State private var renamePlaylistName = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Playlists")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    showingCreatePlaylist = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            
            if playlistService.isLoading {
                ProgressView("Loading playlists...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if playlistService.playlists.isEmpty {
                VStack {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("No playlists")
                        .font(.headline)
                        .foregroundColor(.gray)
                    Text("Create your first playlist to get started")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(playlistService.playlists, id: \.id) { playlist in
                    PlaylistRowView(playlist: playlist) {
                        selectedPlaylist = playlist
                        renamePlaylistName = playlist.name
                        showingRenamePlaylist = true
                    } onDelete: {
                        deletePlaylist(playlist)
                    }
                }
            }
        }
        .alert("Create Playlist", isPresented: $showingCreatePlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                createPlaylist()
            }
        } message: {
            Text("Enter a name for your new playlist")
        }
        .alert("Rename Playlist", isPresented: $showingRenamePlaylist) {
            TextField("Playlist name", text: $renamePlaylistName)
            Button("Cancel", role: .cancel) {
                renamePlaylistName = ""
            }
            Button("Rename") {
                renamePlaylist()
            }
        } message: {
            Text("Enter a new name for the playlist")
        }
        .onAppear {
            loadPlaylists()
        }
    }
    
    private func loadPlaylists() {
        Task {
            do {
                try await playlistService.loadPlaylists()
            } catch {
                print("Error loading playlists: \(error)")
            }
        }
    }
    
    private func createPlaylist() {
        guard !newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            do {
                _ = try await playlistService.createPlaylist(name: newPlaylistName)
                newPlaylistName = ""
            } catch {
                print("Error creating playlist: \(error)")
            }
        }
    }
    
    private func renamePlaylist() {
        guard let playlist = selectedPlaylist,
              !renamePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        Task {
            do {
                try await playlistService.renamePlaylist(playlistId: playlist.id, newName: renamePlaylistName)
                renamePlaylistName = ""
                selectedPlaylist = nil
            } catch {
                print("Error renaming playlist: \(error)")
            }
        }
    }
    
    private func deletePlaylist(_ playlist: Playlist) {
        Task {
            do {
                try await playlistService.deletePlaylist(playlistId: playlist.id)
            } catch {
                print("Error deleting playlist: \(error)")
            }
        }
    }
}

struct PlaylistRowView: View {
    let playlist: Playlist
    let onRename: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text("\(playlist.trackIds.count) tracks")
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
            
            Spacer()
            
            Menu {
                Button("Rename") {
                    onRename()
                }
                
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PlaylistView(playlistService: PlaylistService())
}
