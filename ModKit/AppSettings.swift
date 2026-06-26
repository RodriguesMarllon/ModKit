import Foundation
import SwiftUI

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    @AppStorage("mk.addressBase") var addressBase: Int = 1
    private init() {}
}
