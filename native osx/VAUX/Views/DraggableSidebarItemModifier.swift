import SwiftUI
import CoreTransferable

@available(macOS 13.0, *)
struct DraggableSidebarItemModifier: ViewModifier {
    let kind: SidebarDragPayload.Kind
    let id: String
    
    func body(content: Content) -> some View {
        // Deprecated: Sidebar now uses legacy .onDrag directly in PlaylistSidebar for better responsiveness.
        content
    }
}

@available(macOS 13.0, *)
private struct DragPreview: View {
    let kind: SidebarDragPayload.Kind
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind == .playlist ? "music.note.list" : "folder")
                .foregroundColor(.accentColor)
            Text(kind == .playlist ? "Playlist" : "Folder")
                .font(.caption)
        }
        .padding(6)
        .background(.regularMaterial)
        .cornerRadius(6)
        .shadow(radius: 1)
    }
}

@available(macOS 13.0, *)
extension View {
    func draggableSidebarItem(kind: SidebarDragPayload.Kind, id: String) -> some View {
        self.modifier(DraggableSidebarItemModifier(kind: kind, id: id))
    }
}


