//
//  RestoreBackupMenuState.swift
//  VAUX
//

import Foundation
import SwiftUI

struct RestoreBackupMenuEntry: Identifiable {
    let id: URL
    let url: URL
    let menuTitle: String
}

/// Drives the File → Restore from Backup submenu (Application Support auto-backups).
final class RestoreBackupMenuState: ObservableObject {
    @Published private(set) var entries: [RestoreBackupMenuEntry] = []
    
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    
    func refresh(collectionService: CollectionService) {
        guard collectionService.getActiveCollection() != nil else {
            entries = []
            return
        }
        do {
            let urls = try collectionService.sortedAutoBackupFileURLs()
            entries = urls.map { url in
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let name = url.lastPathComponent
                let title = "\(Self.dateFormatter.string(from: mod)) — \(name)"
                return RestoreBackupMenuEntry(id: url, url: url, menuTitle: title)
            }
        } catch {
            entries = []
        }
    }
}
