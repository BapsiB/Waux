import Foundation

struct PlaylistFolder: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var parentFolderId: String? // nil for root level folders
    var dateCreated: Date
    var dateModified: Date
    var isExpanded: Bool // UI state for expand/collapse
    
    init(id: String = UUID().uuidString, name: String, parentFolderId: String? = nil, isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.parentFolderId = parentFolderId
        self.dateCreated = Date()
        self.dateModified = Date()
        self.isExpanded = isExpanded
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PlaylistFolder, rhs: PlaylistFolder) -> Bool {
        return lhs.id == rhs.id
    }
}