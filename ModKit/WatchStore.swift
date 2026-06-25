import Foundation
import SwiftUI

// MARK: - WatchType

enum WatchType: Codable, Hashable {
    case register
    case bit(Int)

    var label: String {
        switch self {
        case .register:   return "Register"
        case .bit(let i): return "Bit \(i)"
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

    var addressLabel: String {
        "4\(String(format: "%04d", Int(address) + 1))"
    }

    func currentValue(from rows: [RegisterRow]) -> UInt16? {
        rows.first(where: { $0.address == address }).map(\.value)
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
