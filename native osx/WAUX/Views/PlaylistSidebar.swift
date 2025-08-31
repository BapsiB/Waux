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
    @State private var showingExportSheet = false
    @State private var playlistToRename: Playlist?
    @State private var playlistToDuplicate: Playlist?
    @State private var playlistToExport: Playlist?
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
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppStyle.mainColor)
                }
                .buttonStyle(PlainButtonStyle())
                .focusable(false)
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
                        
                        Button("Export") {
                            playlistToExport = playlist
                            showingExportSheet = true
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
                        .background(Color(.controlBackgroundColor))
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
