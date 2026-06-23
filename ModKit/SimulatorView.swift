import SwiftUI

struct SimulatorView: View {
    @ObservedObject var session: SimulatorSession

    var body: some View {
        VStack(spacing: 0) {
            SimControlBar(session: session)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            Divider()

            if session.isRunning {
                SimStatsBar(session: session)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.bar)
                Divider()
                SimRegisterGrid(session: session)
                SimPager(session: session)
                    .padding(.vertical, 10)
            } else {
                SimEmptyState()
            }
        }
        .sheet(item: $session.editTarget) { reg in
            SimEditView(reg: reg, session: session)
        }
    }
}

// MARK: - Control bar

private struct SimControlBar: View {
    @ObservedObject var session: SimulatorSession

    var body: some View {
        HStack(spacing: 12) {
            LabeledField("Modbus Port") {
                TextField("502", text: $session.portStr)
                    .frame(width: 70)
                    .disabled(session.isRunning)
            }

            if let err = session.errorMsg {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button(session.isRunning ? "Stop Server" : "Start Server") {
                session.isRunning ? session.stop() : session.start()
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isRunning ? .red : .green)

            Circle()
                .fill(session.isRunning ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
        }
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: - Stats bar

private struct SimStatsBar: View {
    @ObservedObject var session: SimulatorSession

    var body: some View {
        HStack(spacing: 20) {
            simStat("Listening on", "0.0.0.0:\(session.portStr)")
            simStat("Last client", session.lastClient)
            simStat("Reads", "\(session.readCount)")
            simStat("Writes", "\(session.writeCount)")
            simStat("Uptime", session.uptimeStr)
            Spacer()
            Button("Reset All") {
                let alert = NSAlert()
                alert.messageText = "Reset all 2000 registers to 0?"
                alert.addButton(withTitle: "Reset")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    session.resetAll()
                }
            }
            .foregroundStyle(.red)
        }
    }

    private func simStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - Register grid

private struct SimRegisterGrid: View {
    @ObservedObject var session: SimulatorSession

    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(session.pageRegisters) { reg in
                    SimRegCell(reg: reg)
                        .onTapGesture { session.editTarget = reg }
                }
            }
            .padding(16)
        }
    }
}

private struct SimRegCell: View {
    let reg: SimRegister

    var body: some View {
        VStack(spacing: 4) {
            Text(reg.addressLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(reg.value)")
                .font(.system(size: 18, weight: reg.value != 0 ? .bold : .regular))
                .foregroundStyle(reg.value != 0 ? Color.primary : Color.secondary)
            Text(reg.hexLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            reg.value != 0 ? Color.green.opacity(0.6) : Color(nsColor: .separatorColor),
                            lineWidth: 1
                        )
                )
        )
    }
}

// MARK: - Pager

private struct SimPager: View {
    @ObservedObject var session: SimulatorSession

    var body: some View {
        HStack(spacing: 12) {
            Button("← Prev") { session.page = max(0, session.page - 1) }
                .disabled(session.page == 0)
            Text("Page \(session.page + 1) / \(session.pageCount)  ·  Regs \(session.page * session.pageSize + 1)–\(min((session.page + 1) * session.pageSize, 2000))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
            Button("Next →") { session.page = min(session.pageCount - 1, session.page + 1) }
                .disabled(session.page == session.pageCount - 1)
        }
    }
}

// MARK: - Empty state

private struct SimEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Start the server to simulate a Modbus TCP slave")
                .foregroundStyle(.secondary)
            Text("Other devices can connect and read/write your registers")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Edit sheet

struct SimEditView: View {
    let reg: SimRegister
    @ObservedObject var session: SimulatorSession
    @Environment(\.dismiss) private var dismiss

    @State private var decStr = ""
    @State private var hexStr = ""
    @State private var bits: [Bool] = Array(repeating: false, count: 16)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Register \(reg.addressLabel)").font(.headline)
                    Text("Current: \(reg.value)  (0x\(reg.hexLabel))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding([.horizontal, .top], 20).padding(.bottom, 16)

            Divider()

            // Decimal + Hex
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decimal  (0 – 65535)").font(.caption).foregroundStyle(.secondary)
                        TextField("0", text: $decStr)
                            .textFieldStyle(.roundedBorder).frame(width: 120)
                            .onChange(of: decStr) { v in
                                if let n = UInt16(v) {
                                    hexStr = String(format: "%04X", n)
                                    updateBits(n)
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hex  (0000 – FFFF)").font(.caption).foregroundStyle(.secondary)
                        TextField("0000", text: $hexStr)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                            .onChange(of: hexStr) { v in
                                if let n = UInt16(v.uppercased(), radix: 16) {
                                    decStr = "\(n)"
                                    updateBits(n)
                                }
                            }
                    }
                }

                // Bit grid
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bits").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach((0..<16).reversed(), id: \.self) { b in
                            Button {
                                bits[b].toggle()
                                let v = bitsToValue()
                                decStr = "\(v)"
                                hexStr = String(format: "%04X", v)
                            } label: {
                                VStack(spacing: 2) {
                                    Text("\(b)").font(.system(size: 9)).foregroundStyle(.secondary)
                                    Text(bits[b] ? "1" : "0")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(bits[b] ? Color.black : Color.primary)
                                }
                                .frame(width: 26, height: 34)
                                .background(bits[b] ? Color.green : Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.escape)
                Button("Save") {
                    if let v = UInt16(decStr) {
                        session.setRegister(index: reg.index, value: v)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 480)
        .onAppear {
            decStr = "\(reg.value)"
            hexStr = reg.hexLabel
            updateBits(reg.value)
        }
    }

    private func updateBits(_ v: UInt16) {
        for i in 0..<16 { bits[i] = (v >> i) & 1 == 1 }
    }

    private func bitsToValue() -> UInt16 {
        bits.enumerated().reduce(UInt16(0)) { acc, pair in
            acc | (pair.element ? (1 << pair.offset) : 0)
        }
    }
}
