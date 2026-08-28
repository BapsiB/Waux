import SwiftUI
import UniformTypeIdentifiers

// Test file to verify drag-and-drop functionality
struct DragDropTest: View {
    @StateObject private var playlistService = PlaylistService()
    @State private var selectedItem: SelectableItem?
    
    var body: some View {
        VStack {
            Text("Drag-and-Drop Test")
                .font(.title)
            
            Text("This view tests the drag-and-drop functionality for playlists and folders")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Test the PlaylistSidebar with drag-and-drop
            PlaylistSidebar(
                playlistService: playlistService,
                selectedItem: $selectedItem
            )
            .frame(width: 300, height: 400)
            .border(Color.gray)
            
            // Test validation methods
            Button("Test Validation Logic") {
                testValidationLogic()
            }
            .padding()
        }
        .padding()
    }
    
    private func testValidationLogic() {
        print("Testing drag-and-drop validation logic...")
        
        // Create test folders and playlists
        let folder1 = PlaylistFolder(
            id: "folder1",
            name: "Folder 1",
            parentFolderId: nil,
            isExpanded: true
        )
        
        let folder2 = PlaylistFolder(
            id: "folder2",
            name: "Folder 2",
            parentFolderId: "folder1",
            isExpanded: true
        )
        
        let playlist1 = Playlist(
            id: "playlist1",
            name: "Playlist 1",
            trackIds: [],
            folderId: nil
        )
        
        // Test descendant folder detection
        playlistService.folders = [folder1, folder2]
        playlistService.playlists = [playlist1]
        
        // This should return true (folder2 is descendant of folder1)
        let isDescendant = isDescendantFolder(childId: "folder2", ancestorId: "folder1")
        print("Is folder2 descendant of folder1: \(isDescendant)")
        
        // This should return false (folder1 is not descendant of folder2)
        let isNotDescendant = isDescendantFolder(childId: "folder1", ancestorId: "folder2")
        print("Is folder1 descendant of folder2: \(isNotDescendant)")
        
        print("Validation logic test completed")
    }
    
    // Helper method to check if a folder is a descendant of another folder
    private func isDescendantFolder(childId: String, ancestorId: String) -> Bool {
        guard let childFolder = playlistService.folders.first(where: { $0.id == childId }) else {
            return false
        }
        
        var currentParentId = childFolder.parentFolderId
        while let parentId = currentParentId {
            if parentId == ancestorId {
                return true
            }
            currentParentId = playlistService.folders.first(where: { $0.id == parentId })?.parentFolderId
        }
        
        return false
    }
}

#Preview {
    DragDropTest()
}