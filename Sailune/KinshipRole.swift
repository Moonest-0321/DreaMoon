import Foundation

// MARK: - 固定血緣關係 Enum (兼顧 UI 直覺與佈局方向)
enum KinshipRole: String, Codable, CaseIterable, Identifiable {

    // 【正向：Source 是長輩】
    case fatherToChild = "fatherToChild"
    case motherToChild = "motherToChild"
    case grandparentToGrandchild = "grandparentToGrandchild"

    // 【反向：Source 是晚輩】
    case childToFather = "childToFather"
    case childToMother = "childToMother"
    case grandchildToGrandparent = "grandchildToGrandparent"

    // 【同輩】
    case brothers = "brothers"
    case sisters = "sisters"
    case siblingMixed = "siblingMixed"

    // 【舊版兼容：確保舊資料庫不會崩潰】
    case parent = "父母"
    case child = "子女"
    case sibling = "兄弟姊妹"
    case grandparent = "祖父母/外祖父母"
    case grandchild = "孫子女/外孫子女"

    var id: String { rawValue }

    /// UI 顯示名稱（正反關係顯示相同的詞）
    var displayName: String {
        switch self {
        case .fatherToChild, .childToFather:
            return "父子/父女"
        case .motherToChild, .childToMother:
            return "母子/母女"
        case .grandparentToGrandchild, .grandchildToGrandparent:
            return "祖孫"
        case .brothers:
            return "兄弟"
        case .sisters:
            return "姊妹"
        case .siblingMixed:
            return "兄妹/姊弟"
        // 舊版兼容顯示
        case .parent:
            return "父母"
        case .child:
            return "子女"
        case .sibling:
            return "兄弟姊妹"
        case .grandparent:
            return "祖父母/外祖父母"
        case .grandchild:
            return "孫子女/外孫子女"
        }
    }

    /// 雙向自動反向推導
    var inverseRole: KinshipRole {
        switch self {
        case .fatherToChild: return .childToFather
        case .childToFather: return .fatherToChild
        case .motherToChild: return .childToMother
        case .childToMother: return .motherToChild
        case .grandparentToGrandchild: return .grandchildToGrandparent
        case .grandchildToGrandparent: return .grandparentToGrandchild
        case .brothers: return .brothers
        case .sisters: return .sisters
        case .siblingMixed: return .siblingMixed
        // 舊版兼容
        case .parent: return .child
        case .child: return .parent
        case .sibling: return .sibling
        case .grandparent: return .grandchild
        case .grandchild: return .grandparent
        }
    }

    /// 供 UI 選擇的列表（只顯示正向與同輩，隱藏反向與舊版）
    static var selectableCases: [KinshipRole] {
        [.fatherToChild, .motherToChild, .grandparentToGrandchild,
         .brothers, .sisters, .siblingMixed]
    }

    /// 是否為長輩方向（用於關係圖將節點畫在上方）
    var isElder: Bool {
        switch self {
        case .fatherToChild, .motherToChild, .grandparentToGrandchild,
             .parent, .grandparent:
            return true
        default:
            return false
        }
    }

    /// 是否為晚輩方向（用於關係圖將節點畫在下方）
    var isJunior: Bool {
        switch self {
        case .childToFather, .childToMother, .grandchildToGrandparent,
             .child, .grandchild:
            return true
        default:
            return false
        }
    }
}
