import Foundation
import SwiftUI

struct TagDefinition: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: Color?
    
    init(id: UUID = UUID(), name: String, color: Color? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorValue
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let colorValue = try container.decodeIfPresent(Int.self, forKey: .colorValue) {
            color = Color(hex: colorValue)
        } else {
            color = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        if let color = color {
            try container.encode(color.toHex(), forKey: .colorValue)
        }
    }
}


