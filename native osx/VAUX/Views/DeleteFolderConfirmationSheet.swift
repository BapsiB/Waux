import SwiftUI

struct DeleteFolderConfirmationSheet: View {
    let folder: PlaylistFolder
    let playlistCount: Int
    let subfolderCount: Int
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    private var hasContents: Bool {
        playlistCount > 0 || subfolderCount > 0
    }
    
    private var contentsDescription: String {
        var parts: [String] = []
        if playlistCount > 0 {
            parts.append("\(playlistCount) playlist\(playlistCount == 1 ? "" : "s")")
        }
        if subfolderCount > 0 {
            parts.append("\(subfolderCount) subfolder\(subfolderCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: " and ")
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Delete Folder")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                Text("Are you sure you want to delete \"\(folder.name)\"?")
                    .font(.body)
                    .multilineTextAlignment(.center)
                
                if hasContents {
                    Text("This folder contains \(contentsDescription). All contents will be moved to the parent level.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("This folder is empty and will be permanently deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}