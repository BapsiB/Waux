import SwiftUI
import UniformTypeIdentifiers

struct PlaylistSidebar: View {
    @ObservedObject var playlistService: PlaylistService
    @Binding var selectedPlaylist: Playlist?
    @State private var showingCreatePlaylistSheet = false
    @State private var newPlaylistName = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingRenameSheet = false
    @State private var showingDuplicateSheet = false
    @State private var playlistToRename: Playlist?
    @State private var playlistToDuplicate: Playlist?
    @State private var renamePlaylistName = ""
    @State private var duplicatePlaylistName = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("Playlists")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    newPlaylistName = ""
                    showingCreatePlaylistSheet = true
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
                    .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                        handleDrop(providers: providers, into: playlist)
                    }
                    .contextMenu {
                        Button("Rename") {
                            playlistToRename = playlist
                            renamePlaylistName = playlist.name
                            showingRenameSheet = true
                        }
                        
                        Button("Duplicate") {
                            playlistToDuplicate = playlist
                            duplicatePlaylistName = "\(playlist.name) Copy"
                            showingDuplicateSheet = true
                        }
                        
                        Divider()
                        
                        Button("Delete", role: .destructive) {
                            deletePlaylist(playlist)
                        }
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .frame(width: 200)
        .background(Color(.controlBackgroundColor))
        .sheet(isPresented: $showingCreatePlaylistSheet) {
            CreatePlaylistSheet(
                newPlaylistName: $newPlaylistName,
                onCancel: {
                    showingCreatePlaylistSheet = false
                },
                onCreate: {
                    createPlaylist()
                    showingCreatePlaylistSheet = false
                }
            )
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenamePlaylistSheet(
                playlistName: $renamePlaylistName,
                onCancel: {
                    showingRenameSheet = false
                    playlistToRename = nil
                },
                onRename: {
                    renamePlaylist()
                    showingRenameSheet = false
                    playlistToRename = nil
                }
            )
        }
        .sheet(isPresented: $showingDuplicateSheet) {
            DuplicatePlaylistSheet(
                playlistName: $duplicatePlaylistName,
                onCancel: {
                    showingDuplicateSheet = false
                    playlistToDuplicate = nil
                },
                onDuplicate: {
                    duplicatePlaylist()
                    showingDuplicateSheet = false
                    playlistToDuplicate = nil
                }
            )
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
                _ = try await playlistService.createPlaylist(name: trimmedName)
                // Playlist is created but not automatically selected
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func renamePlaylist() {
        guard let playlist = playlistToRename else { return }
        
        let trimmedName = renamePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errorMessage = "Playlist name cannot be empty"
            showingErrorAlert = true
            return
        }
        
        Task {
            do {
                try await playlistService.renamePlaylist(playlistId: playlist.id, newName: trimmedName)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func duplicatePlaylist() {
        guard let playlist = playlistToDuplicate else { return }
        
        let trimmedName = duplicatePlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errorMessage = "Playlist name cannot be empty"
            showingErrorAlert = true
            return
        }
        
        Task {
            do {
                let newPlaylist = try await playlistService.duplicatePlaylist(playlistId: playlist.id, newName: trimmedName)
                // Optionally select the new playlist
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
    
    private func deletePlaylist(_ playlist: Playlist) {
        Task {
            do {
                try await playlistService.deletePlaylist(playlistId: playlist.id)
                // If the deleted playlist was selected, clear the selection
                await MainActor.run {
                    if selectedPlaylist?.id == playlist.id {
                        selectedPlaylist = nil
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider], into playlist: Playlist) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let nsText = object as? NSString else { return }
                    let text = nsText as String
                    let paths = text
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    if paths.isEmpty { return }
                    Task {
                        for path in paths {
                            do {
                                try await playlistService.addTrackToPlaylist(playlistId: playlist.id, absoluteTrackPath: path)
                            } catch {
                                await MainActor.run {
                                    errorMessage = error.localizedDescription
                                    showingErrorAlert = true
                                }
                            }
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }
}

struct CreatePlaylistSheet: View {
    @Binding var newPlaylistName: String
    @FocusState private var isTextFieldFocused: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Playlist")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a name for your new playlist")
                .font(.body)
                .foregroundColor(.secondary)
            
            TextField("Playlist name", text: $newPlaylistName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onCreate()
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Create") {
                    onCreate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            // Automatically focus the text field when the sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

struct RenamePlaylistSheet: View {
    @Binding var playlistName: String
    @FocusState private var isTextFieldFocused: Bool
    let onCancel: () -> Void
    let onRename: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Playlist")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a new name for the playlist")
                .font(.body)
                .foregroundColor(.secondary)
            
            TextField("Playlist name", text: $playlistName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onRename()
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Rename") {
                    onRename()
                }
                .buttonStyle(.borderedProminent)
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            // Automatically focus the text field when the sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

struct DuplicatePlaylistSheet: View {
    @Binding var playlistName: String
    @FocusState private var isTextFieldFocused: Bool
    let onCancel: () -> Void
    let onDuplicate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Duplicate Playlist")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a name for the duplicated playlist")
                .font(.body)
                .foregroundColor(.secondary)
            
            TextField("Playlist name", text: $playlistName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    if !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onDuplicate()
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Duplicate") {
                    onDuplicate()
                }
                .buttonStyle(.borderedProminent)
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
        .onAppear {
            // Automatically focus the text field when the sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}
