import SwiftUI

struct FolderContextMenu: View {
    let folder: PlaylistFolder
    let onRename: () -> Void
    let onDelete: () -> Void
    let onCreateSubfolder: () -> Void
    
    var body: some View {
        Group {
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
}