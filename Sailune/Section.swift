import Foundation
import SwiftData

@Model
final class Section {
    var id: UUID = UUID()
    var title: String = ""           // 節名 (例如：第一節、相遇)
    
    // 【核心內容】PRD 2.2 規定使用 AttributedString，儲存文字與「幕標題/內文」字體屬性。
    var content: AttributedString = AttributedString("")
    
    var sortOrder: Int = 0           // 排序順序
    var wordCount: Int = 0           // 字數
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    
    // 【反向關聯】這節屬於哪一卷？可選是為了 CloudKit。
    var volume: Volume? = nil

    init(
        id: UUID = UUID(),
        title: String,
        content: AttributedString = AttributedString(""),
        sortOrder: Int = 0,
        wordCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        volume: Volume? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.sortOrder = sortOrder
        self.wordCount = wordCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.volume = volume
    }
}
