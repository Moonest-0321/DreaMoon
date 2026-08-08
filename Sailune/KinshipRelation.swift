import Foundation
import SwiftData

@Model
final class KinshipRelation {
    var id: UUID = UUID()

    var roleRawValue: String = KinshipRole.fatherToChild.rawValue

    var role: KinshipRole {
        get { KinshipRole(rawValue: roleRawValue) ?? .siblingMixed }
        set { roleRawValue = newValue.rawValue }
    }

    // 指向目標角色
    var targetCharacter: Character?

    // 反向關聯回所屬角色
    var sourceCharacter: Character?

    init(role: KinshipRole, targetCharacter: Character? = nil) {
        self.id = UUID()
        self.roleRawValue = role.rawValue
        self.targetCharacter = targetCharacter
    }
}
