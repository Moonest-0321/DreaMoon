import Foundation
import SwiftData

@Model
final class Volume {
    var id: UUID = UUID()
    var title: String = ""       // 卷名 (例如：第一卷、序章)
    var sortOrder: Int = 0       // 排序順序
    var createdAt: Date = Date() // 建立時間
    
    // 【反向關聯】這卷屬於哪一本書？可選是為了 CloudKit 與初始化方便。
    var book: Book? = nil
    
    // 【核心關聯】一卷包含很多節 (Section)，cascade 級聯刪除。
    @Relationship(deleteRule: .cascade, inverse: \Section.volume)
    var sections: [Section] = []
    
    init(
        id: UUID = UUID(),
        title: String,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        book: Book? = nil,
        sections: [Section] = []
    ) {
        self.id = id
        self.title = title
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.book = book
        self.sections = sections
    }
}
