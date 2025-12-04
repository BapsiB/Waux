import SwiftUI

/// Demo view showing how to integrate folder management components
/// This can be used as a reference for integrating into PlaylistSidebar
struct FolderManagementDemo: View {
    @ObservedObject var playlistService: PlaylistService
    
    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Text("Folders")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: {
                        // This would trigger folder creation
                    }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Create new folder")
                }
                .padding()
                
                if playlistService.folders.isEmpty {
                    VStack {
                        Image(systemName: "folder")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                        Text("No folders")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(rootFolders, id: \.id) { folder in
                            FolderRowView(
                                folder: folder,
                                depth: 0,
                                isExpanded: playlistService.folderExpandedStates[folder.id] ?? true,
                                playlistCount: getPlaylistCount(in: folder),
                                subfolderCount: getSubfolderCount(in: folder),
                                onToggleExpansion: {
                                    toggleFolderExpansion(folder)
                                },
                                onRename: {
                                    // Handle rename
                                },
                                onDelete: {
                                    // Handle delete
                                },
                                onCreateSubfolder: {
                                    // Handle create subfolder
                                }
                            )
                        }
                    }
                    .listStyle(SidebarListStyle())
                }
            }
            
            // Overlay the folder management view for handling sheets
            FolderManagementView(playlistService: playlistService)
        }
    }
    
    // MARK: - Helper Properties
    
    private var rootFolders: [PlaylistFolder] {
        playlistService.folders.filter { $0.parentFolderId == nil }
    }
    
    // MARK: - Helper Methods
    
    private func getSubfolders(of folder: PlaylistFolder) -> [PlaylistFolder] {
        return playlistService.folders.filter { $0.parentFolderId == folder.id }
    }
    
    private func getPlaylists(in folder: PlaylistFolder) -> [Playlist] {
        return playlistService.playlists.filter { $0.folderId == folder.id }
    }
    
    private func getPlaylistCount(in folder: PlaylistFolder) -> Int {
        return playlistService.playlists.filter { $0.folderId == folder.id }.count
    }
    
    private func getSubfolderCount(in folder: PlaylistFolder) -> Int {
        return playlistService.folders.filter { $0.parentFolderId == folder.id }.count
    }
    
    private func toggleFolderExpansion(_ folder: PlaylistFolder) {
        let currentState = playlistService.folderExpandedStates[folder.id] ?? true
        playlistService.folderExpandedStates[folder.id] = !currentState
    }
}