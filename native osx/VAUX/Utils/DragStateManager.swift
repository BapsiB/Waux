import Foundation
import Combine

@MainActor
final class DragStateManager: ObservableObject {
    static let shared = DragStateManager()
    
    enum DragKind {
        case none
        case track
        case playlist
        case folder
    }
    
    @Published var currentDrag: DragKind = .none {
        didSet {
            log("state_changed -> \(describe(currentDrag))")
        }
    }
    
    var isOrganizationalDrag: Bool {
        switch currentDrag {
        case .playlist, .folder:
            return true
        default:
            return false
        }
    }
    
    func beginTrackDrag() {
        log("beginTrackDrag()")
        currentDrag = .track
    }
    
    func beginPlaylistDrag() {
        log("beginPlaylistDrag()")
        currentDrag = .playlist
    }
    
    func beginFolderDrag() {
        log("beginFolderDrag()")
        currentDrag = .folder
    }
    
    func reset() {
        log("reset()")
        currentDrag = .none
    }

    private func describe(_ kind: DragKind) -> String {
        switch kind {
        case .none: return "none"
        case .track: return "track"
        case .playlist: return "playlist"
        case .folder: return "folder"
        }
    }
    
    private func log(_ message: String) {
        print("🛰️ [DragStateManager] \(message)")
    }
}


