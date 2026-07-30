import Foundation
import SwiftData

@Model
final class AuthorProfile {
    
    var id: UUID = UUID()
    var penName: String = ""
    
    // Keep this optional for compatibility with stores created before the field was made required.
    var bio: String?
    
    var avatarData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    init(
        penName: String,
        bio: String = "",
        avatarData: Data? = nil
    ) {
        self.id = UUID()
        self.penName = penName
        self.bio = bio
        self.avatarData = avatarData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
