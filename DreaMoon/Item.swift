//
//  Item.swift
//  DreaMoon
//
//  Created by 徐承佑 on Minguo 115/7/20.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
