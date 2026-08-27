import Foundation

enum TrackDragItemProvider {
    /// Registers `public.file-url` for each existing local file (so Finder and DAWs accept the drop)
    /// and `public.plainText` with newline-separated paths for in-app targets (e.g. playlists).
    static func make(for tracks: [Track]) -> NSItemProvider {
        let provider = NSItemProvider()

        let paths = tracks.map(\.path).filter { !$0.isEmpty }
        let payload = paths.joined(separator: "\n")
        if !payload.isEmpty {
            provider.registerObject(payload as NSString, visibility: .all)
        }

        let fm = FileManager.default
        for track in tracks where !track.isUrl {
            let path = track.path
            guard !path.isEmpty, fm.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            _ = provider.registerObject(url as NSURL, visibility: .all)
        }

        Task { @MainActor in
            DragStateManager.shared.beginTrackDrag()
        }

        return provider
    }
}
