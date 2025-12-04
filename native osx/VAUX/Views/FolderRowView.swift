import SwiftUI

struct FolderRowView: View {
    let folder: PlaylistFolder
    let depth: Int
    let isExpanded: Bool
    let playlistCount: Int
    let subfolderCount: Int
    let onToggleExpansion: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onCreateSubfolder: () -> Void
    
    private var indentationWidth: CGFloat {
        CGFloat(depth * 16)
    }
    
    private var hasChildren: Bool {
        playlistCount > 0 || subfolderCount > 0
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Indentation spacer
            if depth > 0 {
                Spacer()
                    .frame(width: indentationWidth)
            }
            
            // Expansion chevron
            if hasChildren {
                Button(action: onToggleExpansion) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Spacer()
                    .frame(width: 12, height: 12)
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
                    HStack {
                        if playlistCount > 0 {
                            Text("\(playlistCount) playlist\(playlistCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if subfolderCount > 0 {
                            if playlistCount > 0 {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(subfolderCount) folder\(subfolderCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            FolderContextMenu(
                folder: folder,
                onRename: onRename,
                onDelete: onDelete,
                onCreateSubfolder: onCreateSubfolder
            )
        }
    }
}