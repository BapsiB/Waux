import SwiftUI
import UniformTypeIdentifiers

struct PlaylistSidebar: View {
    @ObservedObject var playlistService: PlaylistService
    @Binding var selectedPlaylist: Playlist?
    @State private var showingCreatePlaylistSheet = false
    @State private var showingCreateFolderSheet = false
    @State private var showingRenameSheet = false
    @State private var showingRenameFolderSheet = false
    @State private var showingDuplicateSheet = false
    @State private var showingExportSheet = false
    @State private var newPlaylistName = ""
    @State private var newFolderName = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var playlistToRename: Playlist?
    @State private var folderToRename: PlaylistFolder?
    @State private var playlistToDuplicate: Playlist?
    @State private var playlistToExport: Playlist?
    @State private var renamePlaylistName = ""
    @State private var renameFolderName = ""
    @State private var duplicatePlaylistName = ""
    @State private var parentFolderForNewFolder: PlaylistFolder?
    @State private var parentFolderForNewPlaylist: PlaylistFolder?
    
    // Computed property to generate hierarchical items
    private var hierarchicalItems: [HierarchicalItem] {
        var items: [HierarchicalItem] = []
        
        // Add root-level folders first
        let rootFolders = playlistService.folders.filter { $0.parentFolderId == nil }
        for folder in rootFolders.sorted(by: { $0.name < $1.name }) {
            items.append(HierarchicalItem(type: .folder(folder), depth: 0))
            addChildItems(for: folder, to: &items, depth: 1)
        }
        
        // Add root-level playlists
        let rootPlaylists = playlistService.playlists.filter { $0.folderId == nil }
        for playlist in rootPlaylists.sorted(by: { $0.name < $1.name }) {
            items.append(HierarchicalItem(type: .playlist(playlist), depth: 0))
        }
        
        return items
    }
    
    private func addChildItems(for folder: PlaylistFolder, to items: inout [HierarchicalItem], depth: Int) {
        let isExpanded = playlistService.folderExpandedStates[folder.id] ?? folder.isExpanded
        
        if isExpanded {
            // Add child folders
            let childFolders = playlistService.folders.filter { $0.parentFolderId == folder.id }
            for childFolder in childFolders.sorted(by: { $0.name < $1.name }) {
                items.append(HierarchicalItem(type: .folder(childFolder), depth: depth))
                addChildItems(for: childFolder, to: &items, depth: depth + 1)
            }
            
            // Add playlists in this folder
            let folderPlaylists = playlistService.playlists.filter { $0.folderId == folder.id }
            for playlist in folderPlaylists.sorted(by: { $0.name < $1.name }) {
                items.append(HierarchicalItem(type: .playlist(playlist), depth: depth))
            }
        }
    }
    
    var body: some View {
        VStack {
            HStack {
                Text("Playlists")
                    .font(.headline)
                
                Spacer()
                
                Menu {
                    Button("Create Playlist") {
                        newPlaylistName = ""
                        showingCreatePlaylistSheet = true
                    }
                    
                    Button("Create Folder") {
                        newFolderName = ""
                        parentFolderForNewFolder = nil
                        showingCreateFolderSheet = true
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppStyle.mainColor)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
                .help("Create new playlist or folder")
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
                List {
                    ForEach(hierarchicalItems, id: \.id) { item in
                        HierarchicalItemView(
                            item: item,
                            selectedPlaylist: $selectedPlaylist,
                            playlistService: playlistService,
                            onPlaylistRename: { playlist in
                                playlistToRename = playlist
                                renamePlaylistName = playlist.name
                                showingRenameSheet = true
                            },
                            onPlaylistDuplicate: { playlist in
                                playlistToDuplicate = playlist
                                duplicatePlaylistName = "\(playlist.name) Copy"
                                showingDuplicateSheet = true
                            },
                            onPlaylistExport: { playlist in
                                playlistToExport = playlist
                                showingExportSheet = true
                            },
                            onPlaylistDelete: { playlist in
                                deletePlaylist(playlist)
                            },
                            onFolderRename: { folder in
                                folderToRename = folder
                                renameFolderName = folder.name
                                showingRenameFolderSheet = true
                            },
                            onFolderDelete: { folder in
                                deleteFolder(folder)
                            },
                            onCreateSubfolder: { parentFolder in
                                newFolderName = ""
                                parentFolderForNewFolder = parentFolder
                                showingCreateFolderSheet = true
                            },
                            onCreatePlaylistInFolder: { parentFolder in
                                newPlaylistName = ""
                                parentFolderForNewPlaylist = parentFolder
                                showingCreatePlaylistSheet = true
                            },
                            onDrop: { providers, playlist in
                                handleDrop(providers: providers, into: playlist)
                            }
                        )
                    }
                }
                .listStyle(SidebarListStyle())
                .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
                    handleRootLevelDrop(providers: providers)
                }
            }
        }
        .frame(width: 200)
        .background(Color(.textBackgroundColor))
        .sheet(isPresented: $showingCreatePlaylistSheet) {
            CreatePlaylistSheet(
                newPlaylistName: $newPlaylistName,
                parentFolder: parentFolderForNewPlaylist,
                onCancel: {
                    showingCreatePlaylistSheet = false
                    parentFolderForNewPlaylist = nil
                },
                onCreate: {
                    createPlaylist()
                    showingCreatePlaylistSheet = false
                }
            )
        }
        .sheet(isPresented: $showingCreateFolderSheet) {
            CreateFolderSheet(
                newFolderName: $newFolderName,
                parentFolder: parentFolderForNewFolder,
                onCancel: {
                    showingCreateFolderSheet = false
                    parentFolderForNewFolder = nil
                },
                onCreate: {
                    createFolder()
                    showingCreateFolderSheet = false
                    parentFolderForNewFolder = nil
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
        .sheet(isPresented: $showingExportSheet) {
            ExportPlaylistSheet(
                playlist: playlistToExport,
                playlistService: playlistService,
                onCancel: {
                    showingExportSheet = false
                    playlistToExport = nil
                },
                onExportFiles: { destinationURL in
                    exportPlaylistFiles(to: destinationURL)
                    showingExportSheet = false
                    playlistToExport = nil
                },
                onExportCSV: { destinationURL in
                    exportPlaylistCSV(to: destinationURL)
                    showingExportSheet = false
                    playlistToExport = nil
                }
            )
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task {
                do {
                    try await playlistService.loadFolders()
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showingErrorAlert = true
                    }
                }
            }
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
                _ = try await playlistService.createPlaylist(name: trimmedName, folderId: parentFolderForNewPlaylist?.id)
                // Playlist is created but not automatically selected
                // Clear the parent folder reference
                await MainActor.run {
                    parentFolderForNewPlaylist = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func createFolder() {
        let trimmedName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            errorMessage = "Folder name cannot be empty"
            showingErrorAlert = true
            return
        }
        
        Task {
            do {
                _ = try await playlistService.createFolder(name: trimmedName, parentFolderId: parentFolderForNewFolder?.id)
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
                try await playlistService.renameFolder(folderId: folder.id, newName: trimmedName)
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
    
    private func deleteFolder(_ folder: PlaylistFolder) {
        Task {
            do {
                try await playlistService.deleteFolder(folderId: folder.id)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func exportPlaylistFiles(to destinationURL: URL) {
        guard let playlist = playlistToExport else { return }
        
        Task {
            do {
                try await playlistService.exportPlaylistFiles(playlistId: playlist.id, destinationURL: destinationURL)
                await MainActor.run {
                    // Show success message or notification
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingErrorAlert = true
                }
            }
        }
    }
    
    private func exportPlaylistCSV(to destinationURL: URL) {
        guard let playlist = playlistToExport else { return }
        
        Task {
            do {
                try await playlistService.exportPlaylistCSV(playlistId: playlist.id, destinationURL: destinationURL)
                await MainActor.run {
                    // Show success message or notification
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
        print("🔍 [PlaylistSidebar] handleDrop called:")
        print("   - Playlist: \(playlist.name)")
        print("   - Providers count: \(providers.count)")
        
        var handled = false
        for (index, provider) in providers.enumerated() {
            print("   - Provider \(index):")
            print("     - Has plainText: \(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))")
            print("     - Registered types: \(provider.registeredTypeIdentifiers)")
            
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                print("   - Loading NSString object...")
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    print("   - loadObject callback:")
                    print("     - Object: \(String(describing: object))")
                    print("     - Error: \(String(describing: error))")
                    print("     - Object type: \(type(of: object))")
                    
                    if let error = error {
                        print("   - ❌ Error loading object: \(error)")
                        return
                    }
                    
                    guard let nsText = object as? NSString else {
                        print("   - ❌ Failed to cast object to NSString")
                        print("     - Object: \(String(describing: object))")
                        return
                    }
                    
                    print("   - ✅ Successfully loaded NSString:")
                    print("     - Length: \(nsText.length)")
                    print("     - Content: '\(nsText)'")
                    
                    let text = nsText as String
                    let paths = text
                        .split(separator: "\n")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    print("   - Parsed paths:")
                    print("     - Count: \(paths.count)")
                    print("     - Paths: \(paths)")
                    
                    if paths.isEmpty { 
                        print("   - ⚠️ No valid paths found")
                        return 
                    }
                    
                    Task {
                        print("   - 🚀 Adding tracks to playlist...")
                        for (pathIndex, path) in paths.enumerated() {
                            do {
                                print("     - Adding path \(pathIndex + 1)/\(paths.count): \(path)")
                                try await playlistService.addTrackToPlaylist(playlistId: playlist.id, absoluteTrackPath: path)
                                print("     - ✅ Successfully added track")
                            } catch {
                                print("     - ❌ Failed to add track: \(error)")
                                await MainActor.run {
                                    errorMessage = error.localizedDescription
                                    showingErrorAlert = true
                                }
                            }
                        }
                        print("   - ✅ Finished adding all tracks")
                    }
                }
                handled = true
            }
        }
        return handled
    }
    
    private func handleRootLevelDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    guard let dragData = object as? String else { return }
                    
                    Task { @MainActor in
                        do {
                            if dragData.hasPrefix("playlist:") {
                                let playlistId = String(dragData.dropFirst("playlist:".count))
                                // Validate that playlist exists and is not already at root level
                                if let playlist = playlistService.playlists.first(where: { $0.id == playlistId }),
                                   playlist.folderId != nil {
                                    try await playlistService.movePlaylistToFolder(playlistId: playlistId, folderId: nil)
                                }
                            } else if dragData.hasPrefix("folder:") {
                                let folderId = String(dragData.dropFirst("folder:".count))
                                // Validate that folder exists and is not already at root level
                                if let folder = playlistService.folders.first(where: { $0.id == folderId }),
                                   folder.parentFolderId != nil {
                                    try await playlistService.moveFolderToFolder(folderId: folderId, parentFolderId: nil)
                                }
                            }
                        } catch {
                            errorMessage = error.localizedDescription
                            showingErrorAlert = true
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    

}

struct CreatePlaylistSheet: View {
    @Binding var newPlaylistName: String
    let parentFolder: PlaylistFolder?
    @FocusState private var isTextFieldFocused: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Playlist")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let folder = parentFolder {
                Text("Creating playlist in folder: \(folder.name)")
                    .font(.body)
                    .foregroundColor(.blue)
            } else {
                Text("Enter a name for your new playlist")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
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

struct ExportPlaylistSheet: View {
    let playlist: Playlist?
    let playlistService: PlaylistService
    let onCancel: () -> Void
    let onExportFiles: (URL) -> Void
    let onExportCSV: (URL) -> Void
    
    @State private var selectedExportType: ExportType = .files
    @State private var showingFilePicker = false
    @State private var showingCSVPicker = false
    
    enum ExportType: String, CaseIterable {
        case files = "files"
        case csv = "csv"
        
        var displayName: String {
            switch self {
            case .files:
                return "Export Files"
            case .csv:
                return "Export CSV"
            }
        }
        
        var description: String {
            switch self {
            case .files:
                return "Copy all audio files to a selected folder"
            case .csv:
                return "Export track metadata to a CSV file"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Playlist")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let playlist = playlist {
                Text("Exporting: \(playlist.name)")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                Text("\(playlist.trackPaths.count) tracks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ExportType.allCases, id: \.self) { exportType in
                    Button(action: {
                        selectedExportType = exportType
                        if exportType == .files {
                            showingFilePicker = true
                        } else {
                            showingCSVPicker = true
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exportType.displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(exportType.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 400)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    onExportFiles(url)
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
        .fileExporter(
            isPresented: $showingCSVPicker,
            document: CSVExportDocument(playlist: playlist, playlistService: playlistService),
            contentType: .commaSeparatedText,
            defaultFilename: playlist?.name ?? "playlist"
        ) { result in
            switch result {
            case .success(let url):
                onExportCSV(url)
            case .failure(let error):
                print("CSV export error: \(error)")
            }
        }
    }
}

// MARK: - Hierarchical Display Support

struct HierarchicalItem: Identifiable {
    enum ItemType {
        case folder(PlaylistFolder)
        case playlist(Playlist)
    }
    
    let type: ItemType
    let depth: Int
    
    var id: String {
        switch type {
        case .folder(let folder):
            return "folder_\(folder.id)"
        case .playlist(let playlist):
            return "playlist_\(playlist.id)"
        }
    }
}

struct HierarchicalItemView: View {
    let item: HierarchicalItem
    @Binding var selectedPlaylist: Playlist?
    @ObservedObject var playlistService: PlaylistService
    let onPlaylistRename: (Playlist) -> Void
    let onPlaylistDuplicate: (Playlist) -> Void
    let onPlaylistExport: (Playlist) -> Void
    let onPlaylistDelete: (Playlist) -> Void
    let onFolderRename: (PlaylistFolder) -> Void
    let onFolderDelete: (PlaylistFolder) -> Void
    let onCreateSubfolder: (PlaylistFolder) -> Void
    let onCreatePlaylistInFolder: (PlaylistFolder) -> Void
    let onDrop: ([NSItemProvider], Playlist) -> Bool
    
    @State private var draggedOver = false
    
    private var indentationWidth: CGFloat {
        CGFloat(item.depth * 16)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Indentation spacer
            if item.depth > 0 {
                Spacer()
                    .frame(width: indentationWidth)
                    .background(Color.red.opacity(0.5)) // DEBUG: Red for indentation
            }
            
            switch item.type {
            case .folder(let folder):
                FolderItemView(
                    folder: folder,
                    playlistService: playlistService,
                    onRename: { onFolderRename(folder) },
                    onDelete: { onFolderDelete(folder) },
                    onCreateSubfolder: { onCreateSubfolder(folder) },
                    onCreatePlaylist: { onCreatePlaylistInFolder(folder) },
                    draggedOver: draggedOver
                )
                .draggable("folder:\(folder.id)")
                .onDrop(of: [UTType.plainText], isTargeted: $draggedOver) { providers in
                    handleFolderDrop(providers: providers, targetFolder: folder)
                }
                
            case .playlist(let playlist):
                PlaylistItemView(
                    playlist: playlist,
                    isSelected: selectedPlaylist?.id == playlist.id,
                    onSelect: { selectedPlaylist = playlist },
                    onRename: { onPlaylistRename(playlist) },
                    onDuplicate: { onPlaylistDuplicate(playlist) },
                    onExport: { onPlaylistExport(playlist) },
                    onDelete: { onPlaylistDelete(playlist) },
                    onDrop: { providers in onDrop(providers, playlist) },
                    draggedOver: draggedOver
                )
                .draggable("playlist:\(playlist.id)")
                .onDrop(of: [UTType.plainText], isTargeted: $draggedOver) { providers in
                    handlePlaylistDrop(providers: providers, targetPlaylist: playlist)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Apply selection highlight at HierarchicalItemView level for full width
            {
                switch item.type {
                case .playlist(let playlist):
                    if selectedPlaylist?.id == playlist.id {
                        return RoundedRectangle(cornerRadius: 6)
                            .fill(AppStyle.secondaryColor.opacity(0.6))
                    } else {
                        return RoundedRectangle(cornerRadius: 6)
                            .fill(Color.clear)
                    }
                case .folder:
                    return RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clear)
                }
            }()
        )
    }
    
    private func handleFolderDrop(providers: [NSItemProvider], targetFolder: PlaylistFolder) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    guard let dragData = object as? String else { return }
                    
                    Task { @MainActor in
                        do {
                            if dragData.hasPrefix("playlist:") {
                                let playlistId = String(dragData.dropFirst("playlist:".count))
                                // Validate that playlist exists and is not already in this folder
                                if let playlist = playlistService.playlists.first(where: { $0.id == playlistId }),
                                   playlist.folderId != targetFolder.id {
                                    try await playlistService.movePlaylistToFolder(playlistId: playlistId, folderId: targetFolder.id)
                                }
                            } else if dragData.hasPrefix("folder:") {
                                let folderId = String(dragData.dropFirst("folder:".count))
                                // Validate that folder exists - circular reference checking is handled by PlaylistService
                                if let folder = playlistService.folders.first(where: { $0.id == folderId }),
                                   folderId != targetFolder.id,
                                   folder.parentFolderId != targetFolder.id {
                                    try await playlistService.moveFolderToFolder(folderId: folderId, parentFolderId: targetFolder.id)
                                }
                            }
                        } catch {
                            print("Error handling folder drop: \(error)")
                            // Error handling should be done at the parent level
                        }
                    }
                }
                return true
            }
        }
        return false
    }
    
    private func handlePlaylistDrop(providers: [NSItemProvider], targetPlaylist: Playlist) -> Bool {
        // First check if this is a drag-and-drop of playlists/folders (for organization)
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    guard let dragData = object as? String else { 
                        // If it's not drag data, fall back to the existing file drop handler
                        return
                    }
                    
                    Task { @MainActor in
                        do {
                            if dragData.hasPrefix("playlist:") {
                                let playlistId = String(dragData.dropFirst("playlist:".count))
                                // Validate that playlist exists and is not the same as target
                                if let playlist = playlistService.playlists.first(where: { $0.id == playlistId }),
                                   playlistId != targetPlaylist.id,
                                   playlist.folderId != targetPlaylist.folderId {
                                    try await playlistService.movePlaylistToFolder(playlistId: playlistId, folderId: targetPlaylist.folderId)
                                }
                            } else if dragData.hasPrefix("folder:") {
                                let folderId = String(dragData.dropFirst("folder:".count))
                                // Validate that folder exists and prevent invalid moves
                                if let folder = playlistService.folders.first(where: { $0.id == folderId }),
                                   folder.parentFolderId != targetPlaylist.folderId {
                                    try await playlistService.moveFolderToFolder(folderId: folderId, parentFolderId: targetPlaylist.folderId)
                                }
                            }
                        } catch {
                            print("Error handling playlist drop: \(error)")
                            // Error handling should be done at the parent level
                        }
                    }
                }
                return true
            }
        }
        
        // Fall back to existing file drop handler
        return onDrop(providers, targetPlaylist)
    }
}

struct FolderItemView: View {
    let folder: PlaylistFolder
    @ObservedObject var playlistService: PlaylistService
    let onRename: () -> Void
    let onDelete: () -> Void
    let onCreateSubfolder: () -> Void
    let onCreatePlaylist: () -> Void
    let draggedOver: Bool
    
    private var isExpanded: Bool {
        playlistService.folderExpandedStates[folder.id] ?? folder.isExpanded
    }
    
    private var hasChildren: Bool {
        let childFolders = playlistService.folders.filter { $0.parentFolderId == folder.id }
        let childPlaylists = playlistService.playlists.filter { $0.folderId == folder.id }
        return !childFolders.isEmpty || !childPlaylists.isEmpty
    }
    
    private var childCount: (folders: Int, playlists: Int) {
        let childFolders = playlistService.folders.filter { $0.parentFolderId == folder.id }
        let childPlaylists = playlistService.playlists.filter { $0.folderId == folder.id }
        return (childFolders.count, childPlaylists.count)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Expansion chevron
            if hasChildren {
                Button(action: toggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Spacer()
                    .frame(width: 12, height: 8)
            }
            
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundColor(.blue)
            
            // Folder name and info
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.headline)
                    .lineLimit(1)
                
                if hasChildren {
                    let counts = childCount
                    HStack {
                        
                        if counts.folders > 0 {
                            if counts.playlists > 0 {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(counts.folders) folder\(counts.folders == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(draggedOver ? Color.blue.opacity(0.5) : Color.clear)
        .overlay(
            draggedOver ? 
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.blue, lineWidth: 2)
                .animation(.easeInOut(duration: 0.2), value: draggedOver)
            : nil
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button("Create Playlist") {
                onCreatePlaylist()
            }
            
            Button("Create Subfolder") {
                onCreateSubfolder()
            }
            
            Divider()
            
            Button("Rename") {
                onRename()
            }
            
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private func toggleExpansion() {
        playlistService.folderExpandedStates[folder.id] = !isExpanded
    }
}

struct PlaylistItemView: View {
    let playlist: Playlist
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool
    let draggedOver: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Playlist icon
            Image(systemName: "music.note.list")
                .font(.system(size: 14))
                .foregroundColor(.orange)
            
            // Playlist info
            VStack(alignment: .leading, spacing: 0) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                
                HStack {
                    
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
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            draggedOver ? Color.green.opacity(0.2) : Color.clear
        )
        .overlay(
            draggedOver ? 
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.green, lineWidth: 2)
                .animation(.easeInOut(duration: 0.2), value: draggedOver)
            : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            onDrop(providers)
        }
        .contextMenu {
            Button("Rename") {
                onRename()
            }
            
            Button("Duplicate") {
                onDuplicate()
            }
            
            Button("Export") {
                onExport()
            }
            
            Divider()
            
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

struct CSVExportDocument: FileDocument {
    let playlist: Playlist?
    let playlistService: PlaylistService
    
    init(playlist: Playlist?, playlistService: PlaylistService) {
        self.playlist = playlist
        self.playlistService = playlistService
    }
    
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    
    init(configuration: ReadConfiguration) throws {
        playlist = nil
        playlistService = PlaylistService()
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let playlist = playlist else {
            return FileWrapper(regularFileWithContents: Data())
        }
        
        // Generate CSV content using the playlist service
        let csvContent = generateCSVContent(for: playlist)
        return FileWrapper(regularFileWithContents: csvContent.data(using: .utf8) ?? Data())
    }
    
    private func generateCSVContent(for playlist: Playlist) -> String {
        // For now, create a simple CSV with just the track paths
        // The actual CSV generation with full metadata is handled in PlaylistService.exportPlaylistCSV
        var csv = "Title,Artist,Album,Album Artist,Composer,Genre,Year,Track Number,Disc Number,BPM,Relative Path,Duration,Rating,Comment,Tags,Date Added\n"
        
        for trackPath in playlist.trackPaths {
            let escapedPath = trackPath.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(escapedPath)\",,,,,,,,,,,,,,\n"
        }
        
        return csv
    }
}
