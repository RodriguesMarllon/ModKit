import SwiftUI

struct RegisterTableView: View {
    @ObservedObject var session: ScanSession
    @ObservedObject var watchStore: WatchStore
    @EnvironmentObject private var settings: AppSettings
    @State private var sortOrder = [KeyPathComparator(\RegisterRow.address)]
    @State private var selection: RegisterRow.ID?
    @State private var watchTarget: RegisterRow?

    var sortedRows: [RegisterRow] {
        session.rows.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if session.rows.isEmpty {
                emptyState
            } else {
                table
            }
        }
    }

    // MARK: Table

    private var table: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Address", value: \.address) { row in
                Text(row.addressLabel(base: settings.addressBase))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 90)

            TableColumn("Decimal", value: \.value) { row in
                Text(row.decLabel)
                    .font(.system(size: 13, weight: row.value != 0 ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(row.value != 0 ? Color.primary : Color.secondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Hex") { row in
                Text(row.hexLabel)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(row.value != 0 ? Color.orange : Color.secondary)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Binary") { row in
                BinaryBitsView(value: row.value)
            }
            .width(min: 180, ideal: 210)
        }
        .contextMenu(forSelectionType: RegisterRow.ID.self) { ids in
            if let id = ids.first,
               let row = session.rows.first(where: { $0.id == id }) {
                Button("Write Register \(row.addressLabel(base: settings.addressBase))...") {
                    session.writeTarget = row
                }
                Divider()
                Button("Add to Watch...") {
                    watchTarget = row
                }
                Divider()
                Button("Copy Decimal") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.decLabel, forType: .string)
                }
                Button("Copy Hex") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(row.hexLabel, forType: .string)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first,
               let row = session.rows.first(where: { $0.id == id }) {
                session.writeTarget = row
            }
        }
        .sheet(item: $watchTarget) { row in
            AddWatchView(row: row, store: watchStore)
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.icloud")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(session.isConnected ? "Press Read or enable Auto-poll" : "Connect to a Modbus device to start scanning")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - BinaryBitsView

private struct BinaryBitsView: View {
    let value: UInt16

    private let nibbles: [[Int]] = [
        [15, 14, 13, 12],
        [11, 10,  9,  8],
        [ 7,  6,  5,  4],
        [ 3,  2,  1,  0],
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(nibbles, id: \.first) { group in
                HStack(spacing: 3) {
                    ForEach(group, id: \.self) { bit in
                        bitCell(bit: bit)
                    }
                }
            }
        }
    }

    private func bitCell(bit: Int) -> some View {
        let isSet = (value >> bit) & 1 == 1
        return VStack(spacing: 1) {
            Text("\(bit)")
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(isSet ? "1" : "0")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isSet ? Color.orange : Color.secondary)
        }
    }
}
