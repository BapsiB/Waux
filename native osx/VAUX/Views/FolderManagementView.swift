import SwiftUI

struct FolderManagementView: View {
    @ObservedObject var playlistService: PlaylistService
    
    // Sheet states
    @State private var showingCreateFolderSheet = false
    @State private var showingRenameFolderSheet = false
    @State private var showingDeleteConfirmationSheet = false
    @State private var showingErrorAlert = false
    
    // Form data
    @State private var newFolderName = ""
    @State private var renameFolderName = ""
    @State private var errorMessage = ""
    
    // Current operations
    @State private var folderToRename: PlaylistFolder?
    @State private var folderToDelete: PlaylistFolder?
    @State private var parentFolderForCreation: PlaylistFolder?
    
    var body: some View {
        EmptyView() // This view is primarily for managing sheets and state
            .sheet(isPresented: $showingCreateFolderSheet) {
                CreateFolderSheet(
                    newFolderName: $newFolderName,
                    parentFolder: parentFolderForCreation,
                    onCancel: {
                        showingCreateFolderSheet = false
                        parentFolderForCreation = nil
                    },
                    onCreate: {
                        createFolder()
                        showingCreateFolderSheet = false
                        parentFolderForCreation = nil
                    }
                )
            }
            .sheet(isPresented: $showingRenameFolderSheet) {
                RenameFolderSheet(
                    folderName: $renameFolderName,
                    onCancel: {
                        showingRenameFolderSheet = false
                        folderToRename = nil
                    },
                    onRename: {
                        renameFolder()
                        showingRenameFolderSheet = false
                        folderToRename = nil
                    }
                )
            }
            .sheet(isPresented: $showingDeleteConfirmationSheet) {
                if let folder = folderToDelete {
                    DeleteFolderConfirmationSheet(
                        folder: folder,
                        playlistCount: getPlaylistCount(in: folder),
                        subfolderCount: getSubfolderCount(in: folder),
                        onCancel: {
                            showingDeleteConfirmationSheet = false
                            folderToDelete = nil
                        },
                        onDelete: {
                            deleteFolder()
                            showingDeleteConfirmationSheet = false
                            folderToDelete = nil
                        }
                    )
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
    }
    
    // MARK: - Public Methods
    
    func createFolder(parentFolder: PlaylistFolder? = nil) {
        parentFolderForCreation = parentFolder
        newFolderName = ""
        showingCreateFolderSheet = true
    }
    
    func renameFolder(_ folder: PlaylistFolder) {
        folderToRename = folder
        renameFolderName = folder.name
        showingRenameFolderSheet = true
    }
    
    func deleteFolder(_ folder: PlaylistFolder) {
        folderToDelete = folder
        showingDeleteConfirmationSheet = true
    }
    
    // MARK: - Private Methods
    
    private func createFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errorMessage = "Folder name cannot be empty"
            showingErrorAlert = true
            return
        }
        
        Task {
            do {
                _ = try await playlistService.createFolder(
                    name: trimmedName,
                    parentFolderId: parentFolderForCreation?.id
                )
            } catch {
                await MainActor.run {
                    errorMessage = FolderErrorHandler.userFriendlyMessage(for: error)
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func renameFolder() {
        guard let folder = folderToRename else { return }
        
        let trimmedName = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errorMessage = "Folder name cannot be empty"
            showingErrorAlert = true
            return
        }
        
        Task {
            do {
                try await playlistService.renameFolder(
                    folderId: folder.id,
                    newName: trimmedName
                )
            } catch {
                await MainActor.run {
                    errorMessage = FolderErrorHandler.userFriendlyMessage(for: error)
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func deleteFolder() {
        guard let folder = folderToDelete else { return }
        
        Task {
            do {
                try await playlistService.deleteFolder(folderId: folder.id)
            } catch {
                await MainActor.run {
                    errorMessage = FolderErrorHandler.userFriendlyMessage(for: error)
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func getPlaylistCount(in folder: PlaylistFolder) -> Int {
        return playlistService.playlists.filter { $0.folderId == folder.id }.count
    }
    
    private func getSubfolderCount(in folder: PlaylistFolder) -> Int {
        return playlistService.folders.filter { $0.parentFolderId == folder.id }.count
    }
}