import Foundation
import CoreTransferable

@available(macOS 13.0, *)
struct SidebarDragPayload: Transferable {
    enum Kind: String {
        case playlist
        case folder
    }
    
    let kind: Kind
    let id: String
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .plainText) { value in
            // Mark organizational drag kind before providing data
            Task { @MainActor in
                switch value.kind {
                case .playlist:
                    DragStateManager.shared.beginPlaylistDrag()
                case .folder:
                    DragStateManager.shared.beginFolderDrag()
                }
            }
            let string = "\(value.kind.rawValue):\(value.id)"
            return string.data(using: .utf8) ?? Data()
        } importing: { data in
            let string = String(data: data, encoding: .utf8) ?? ""
            let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let kind = Kind(rawValue: parts[0]) {
                return SidebarDragPayload(kind: kind, id: parts[1])
            }
            // Fallback (shouldn't happen for outgoing drags)
            return SidebarDragPayload(kind: .playlist, id: string)
        }
    }
}


