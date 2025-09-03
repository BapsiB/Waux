import SwiftUI

// Test file to verify all folder management components compile correctly
// This file can be removed after integration testing

struct FolderManagementTest: View {
    @StateObject private var playlistService = PlaylistService()
    @State private var testFolderName = "Test Folder"
    
    var body: some View {
        VStack {
            Text("Folder Management Components Test")
                .font(.title)
            
            // Test CreateFolderSheet
            CreateFolderSheet(
                newFolderName: $testFolderName,
                parentFolder: nil,
                onCancel: {},
                onCreate: {}
            )
            
            // Test RenameFolderSheet
            RenameFolderSheet(
                folderName: $testFolderName,
                onCancel: {},
                onRename: {}
            )
            
            // Test FolderManagementView
            FolderManagementView(playlistService: playlistService)
        }
    }
}

#Preview {
    FolderManagementTest()
}