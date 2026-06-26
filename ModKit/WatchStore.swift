import Foundation
import SwiftUI

// MARK: - WordOrder

enum WordOrder: String, Codable, Hashable, CaseIterable {
    case abcd
    case cdab

    var label: String {
        switch self {
        case .abcd: return "AB CD  (high first)"
        case .cdab: return "CD AB  (low first)"
        }
    }
}

// MARK: - WatchType

enum WatchType: Codable, Hashable {
    case register
    case bit(Int)
    case float32(WordOrder)

    var label: String {
        switch self {
        case .register:         return "Register"
        case .bit(let i):       return "Bit \(i)"
        case .float32(let wo):  return "Float32 \(wo.rawValue.uppercased())"
        }
    }
}

// MARK: - WatchItem

struct WatchItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var address: UInt16
    var type: WatchType
    var divisor: Double = 1.0

    func addressLabel(base: Int = 1) -> String {
        "4\(String(format: "%04d", Int(address) + base))"
    }

    func currentValue(from rows: [RegisterRow]) -> UInt16? {
        rows.first(where: { $0.address == address }).map(\.value)
    }

    /// Reads two consecutive registers and interprets them as IEEE 754 Float32.
    func float32Value(from rows: [RegisterRow]) -> Float? {
        guard case .float32(let order) = type else { return nil }
        let nextAddress = address &+ 1
        guard let regA = rows.first(where: { $0.address == address }),
              let regB = rows.first(where: { $0.address == nextAddress }) else { return nil }
        let combined: UInt32
        switch order {
        case .abcd: combined = UInt32(regA.value) << 16 | UInt32(regB.value)
        case .cdab: combined = UInt32(regB.value) << 16 | UInt32(regA.value)
        }
        return Float(bitPattern: combined)
    }
}

// MARK: - WatchStore

@MainActor
final class WatchStore: ObservableObject {
    @Published var items: [WatchItem] = []

    private let defaultsKey = "mk.watches"

    init() { load() }

    func add(_ item: WatchItem) {
        items.append(item)
        save()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func update(_ item: WatchItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        save()
    }

    func move(from: IndexSet, to: Int) {
        items.move(fromOffsets: from, toOffset: to)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([WatchItem].self, from: data) else { return }
        items = saved
    }
}
