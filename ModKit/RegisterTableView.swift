import SwiftUI

struct RegisterTableView: View {
    @ObservedObject var session: ScanSession
    @State private var sortOrder = [KeyPathComparator(\RegisterRow.address)]
    @State private var selection: RegisterRow.ID?

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
                Text(row.addressLabel)
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

            TableColumn("Binary (nibbles)") { row in
                Text(row.binLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
            .width(min: 130, ideal: 160)
        }
        .contextMenu(forSelectionType: RegisterRow.ID.self) { ids in
            if let id = ids.first,
               let row = session.rows.first(where: { $0.id == id }) {
                Button("Write Register \(row.addressLabel)...") {
                    session.writeTarget = row
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
