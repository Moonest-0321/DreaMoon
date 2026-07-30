import Foundation
import SwiftData

@Model
final class Character {
    var id: UUID = UUID()
    var isPinned: Bool = false              // 置頂標記
    var sortOrder: Int = 0                  // 手動排序
    
    // 1. 真名 (必填標籤)
    var realName: String = ""
    
    // 2. 出生 (複合欄位子維度，各自獨立選填)
    var birthYear: String?                  // 年
    var birthMonth: String?                 // 月
    var birthDay: String?                   // 日
    var birthSeason: String?                // 季節 (自由文字)
    var originBackground: String?           // 出身 (家族/地位/其他)
    var originStory: String?                // 來歷 (多行自由文字)
    
    // 3. 性別 (選填)
    var gender: String?                     // "男" / "女"
    
    // 4. 小記
    var notes: String?
    
    // 5. 親屬關係 (僅限血緣，Cascade 刪除關聯鏈)
    @Relationship(deleteRule: .cascade, inverse: \KinshipRelation.sourceCharacter)
    var kinships: [KinshipRelation] = []
    
    // 6. 性格 & 7. 原則
    var personality: String?
    var principles: String?
    
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // 所屬書籍
    var book: Book? = nil

    init(realName: String, book: Book? = nil) {
        self.id = UUID()
        self.realName = realName
        self.book = book
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
