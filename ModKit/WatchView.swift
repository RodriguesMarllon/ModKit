import SwiftUI

// MARK: - WatchView

struct WatchView: View {
    @ObservedObject var store: WatchStore
    @ObservedObject var session: ScanSession

    var body: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            watchList
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No watches yet")
                .foregroundStyle(.secondary)
            Text("Right-click a register in the Scanner tab and choose \"Add to Watch...\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Watch list

    private var watchList: some View {
        List {
            ForEach(store.items) { item in
                WatchRow(item: item, rows: session.rows)
                    .contextMenu {
                        Button("Edit Watch...") {
                            editTarget = item
                        }
                        Divider()
                        Button("Remove Watch", role: .destructive) {
                            store.remove(id: item.id)
                        }
                    }
            }
            .onMove { store.move(from: $0, to: $1) }
        }
        .sheet(item: $editTarget) { item in
            EditWatchView(item: item, store: store)
        }
    }

    @State private var editTarget: WatchItem?
}

// MARK: - WatchRow

private struct WatchRow: View {
    let item: WatchItem
    let rows: [RegisterRow]

    private var rawValue: UInt16? { item.currentValue(from: rows) }

    private var displayValue: String {
        guard let raw = rawValue else { return "—" }
        switch item.type {
        case .register:
            if item.divisor != 1.0 {
                let scaled = Double(raw) / item.divisor
                let fmt = scaled.truncatingRemainder(dividingBy: 1) == 0
                    ? String(format: "%.0f", scaled)
                    : String(format: "%.3f", scaled).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                return "\(fmt)  (raw: \(raw))"
            }
            return "\(raw)    0x\(String(format: "%04X", raw))"
        case .bit(let i):
            return "\((raw >> i) & 1)"
        }
    }

    private var isActive: Bool {
        guard let raw = rawValue else { return false }
        switch item.type {
        case .register: return raw != 0
        case .bit(let i): return (raw >> i) & 1 == 1
        }
    }

    private var subtitleLabel: String {
        var parts = "\(item.addressLabel)  ·  \(item.type.label)"
        if item.divisor != 1.0 {
            let d = item.divisor.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", item.divisor)
                : String(item.divisor)
            parts += "  ·  ÷\(d)"
        }
        return parts
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(rawValue == nil ? Color.gray.opacity(0.3) : isActive ? Color.orange : Color.green.opacity(0.6))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitleLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(displayValue)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(rawValue == nil ? Color.secondary : isActive ? Color.orange : Color.primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AddWatchView

struct AddWatchView: View {
    let row: RegisterRow
    let store: WatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var watchKind: WatchKind = .register
    @State private var bitIndex: Int = 0
    @State private var divisorStr: String = "1"

    enum WatchKind { case register, bit }

    private static let presetDivisors: [(label: String, value: Double)] = [
        ("1", 1), ("10", 10), ("100", 100), ("1000", 1000)
    ]

    init(row: RegisterRow, store: WatchStore) {
        self.row = row
        self.store = store
        _name = State(initialValue: row.addressLabel)
    }

    private var divisor: Double { Double(divisorStr) ?? 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Watch")
                .font(.headline)

            LabeledField("Name") {
                TextField("e.g. Voltage L1-L2", text: $name)
                    .frame(width: 220)
            }

            LabeledField("Type") {
                Picker("", selection: $watchKind) {
                    Text("Full Register").tag(WatchKind.register)
                    Text("Bit").tag(WatchKind.bit)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if watchKind == .bit {
                LabeledField("Bit Index (0 = LSB)") {
                    Picker("", selection: $bitIndex) {
                        ForEach(0..<16) { i in
                            let isSet = (row.value >> i) & 1 == 1
                            Text("Bit \(i)  →  \(isSet ? "1" : "0")").tag(i)
                        }
                    }
                    .frame(width: 180)
                }
            }

            if watchKind == .register {
                LabeledField("Scale  ÷") {
                    HStack(spacing: 6) {
                        TextField("1", text: $divisorStr)
                            .frame(width: 70)
                        ForEach(Self.presetDivisors, id: \.label) { preset in
                            Button(preset.label) { divisorStr = preset.label }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(divisorStr == preset.label ? .accentColor : .secondary)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 6) {
                Text("Preview:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(previewValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Add Watch") {
                    let type: WatchType = watchKind == .register ? .register : .bit(bitIndex)
                    let d = watchKind == .register ? (divisor > 0 ? divisor : 1.0) : 1.0
                    store.add(WatchItem(name: name.isEmpty ? row.addressLabel : name,
                                       address: row.address, type: type, divisor: d))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)
    }

    private var previewValue: String {
        switch watchKind {
        case .register:
            let d = divisor > 0 ? divisor : 1.0
            if d != 1.0 {
                let scaled = Double(row.value) / d
                return String(format: "%.3f", scaled) + "  (raw: \(row.value))"
            }
            return "\(row.value)  (0x\(String(format: "%04X", row.value)))"
        case .bit:
            let bit = (row.value >> bitIndex) & 1
            return "\(bit)"
        }
    }
}

// MARK: - EditWatchView

struct EditWatchView: View {
    let store: WatchStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var watchKind: AddWatchView.WatchKind
    @State private var bitIndex: Int
    @State private var divisorStr: String

    private let originalID: UUID

    private static let presetDivisors: [(label: String, value: Double)] = [
        ("1", 1), ("10", 10), ("100", 100), ("1000", 1000)
    ]

    init(item: WatchItem, store: WatchStore) {
        self.store = store
        self.originalID = item.id
        _name = State(initialValue: item.name)
        _divisorStr = State(initialValue: item.divisor == 1.0 ? "1" : String(item.divisor))
        switch item.type {
        case .register:
            _watchKind = State(initialValue: .register)
            _bitIndex = State(initialValue: 0)
        case .bit(let i):
            _watchKind = State(initialValue: .bit)
            _bitIndex = State(initialValue: i)
        }
    }

    private var divisor: Double { Double(divisorStr) ?? 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Watch")
                .font(.headline)

            LabeledField("Name") {
                TextField("Name", text: $name)
                    .frame(width: 220)
            }

            LabeledField("Type") {
                Picker("", selection: $watchKind) {
                    Text("Full Register").tag(AddWatchView.WatchKind.register)
                    Text("Bit").tag(AddWatchView.WatchKind.bit)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if watchKind == .bit {
                LabeledField("Bit Index (0 = LSB)") {
                    Picker("", selection: $bitIndex) {
                        ForEach(0..<16) { i in Text("Bit \(i)").tag(i) }
                    }
                    .frame(width: 180)
                }
            }

            if watchKind == .register {
                LabeledField("Scale  ÷") {
                    HStack(spacing: 6) {
                        TextField("1", text: $divisorStr)
                            .frame(width: 70)
                        ForEach(Self.presetDivisors, id: \.label) { preset in
                            Button(preset.label) { divisorStr = preset.label }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(divisorStr == preset.label ? .accentColor : .secondary)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    let type: WatchType = watchKind == .register ? .register : .bit(bitIndex)
                    let d = watchKind == .register ? (divisor > 0 ? divisor : 1.0) : 1.0
                    store.update(WatchItem(id: originalID, name: name.isEmpty ? "Watch" : name,
                                          address: store.items.first(where: { $0.id == originalID })?.address ?? 0,
                                          type: type, divisor: d))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .textFieldStyle(.roundedBorder)
        .frame(width: 320)
    }
}
