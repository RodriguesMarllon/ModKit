import SwiftUI

enum AppTab { case scanner, simulator }

struct ContentView: View {
    @StateObject private var session = ScanSession()
    @State private var activeTab: AppTab = .scanner

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("Scanner", tab: .scanner, icon: "magnifyingglass")
                tabButton("Simulator", tab: .simulator, icon: "server.rack")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Content
            switch activeTab {
            case .scanner:
                ScannerView(session: session)
            case .simulator:
                SimulatorView()
            }
        }
    }

    private func tabButton(_ label: String, tab: AppTab, icon: String) -> some View {
        Button {
            activeTab = tab
        } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: activeTab == tab ? .semibold : .regular))
                .foregroundStyle(activeTab == tab ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(activeTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ScannerView (extracted from old ContentView body)

struct ScannerView: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar(session: session)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)

            Divider()

            ScanParamsBar(session: session)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            RegisterTableView(session: session)

            Divider()

            StatusBar(session: session)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
        }
        .sheet(item: $session.writeTarget) { row in
            WriteView(row: row, session: session)
        }
    }
}

// MARK: - Connection Bar

private struct ConnectionBar: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        HStack(spacing: 12) {
            Label("ModKit", systemImage: "bolt.horizontal.icloud")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            Divider().frame(height: 20)

            Group {
                LabeledField("IP Address") {
                    TextField("192.168.x.x", text: $session.host)
                        .frame(width: 140)
                }
                LabeledField("Port") {
                    TextField("502", text: $session.portStr)
                        .frame(width: 60)
                }
                LabeledField("Unit ID") {
                    TextField("1", value: $session.unitID, format: .number)
                        .frame(width: 50)
                }
            }
            .disabled(session.isConnected || session.isConnecting)

            Spacer()

            if session.isConnecting {
                ProgressView().scaleEffect(0.6).frame(width: 20)
            }

            Button(session.isConnected ? "Disconnect" : session.isConnecting ? "Cancel" : "Connect") {
                if session.isConnected {
                    session.disconnect()
                } else if session.isConnecting {
                    session.cancelConnect()
                } else {
                    session.connect()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(session.isConnected ? .red : session.isConnecting ? .orange : .accentColor)

            Circle()
                .fill(session.isConnected ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
        }
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: - Scan Params Bar

private struct ScanParamsBar: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        HStack(spacing: 12) {
            LabeledField("Function") {
                Picker("", selection: $session.functionCode) {
                    ForEach([FunctionCode.readHoldingRegisters,
                             .readInputRegisters,
                             .readCoils,
                             .readDiscreteInputs], id: \.rawValue) { fc in
                        Text(fc.label).tag(fc)
                    }
                }
                .frame(width: 230)
            }

            LabeledField("Start Address") {
                TextField("0", text: $session.startAddrStr)
                    .frame(width: 80)
            }

            LabeledField("Count") {
                TextField("50", text: $session.countStr)
                    .frame(width: 60)
            }

            Divider().frame(height: 20)

            Button {
                session.scan()
            } label: {
                Label("Read", systemImage: "arrow.clockwise")
            }
            .disabled(!session.isConnected || session.isBusy)
            .keyboardShortcut("r", modifiers: .command)

            Toggle(isOn: Binding(
                get: { session.autoPoll },
                set: { _ in session.toggleAutoPoll() }
            )) {
                Label("Auto", systemImage: "clock.arrow.2.circlepath")
            }
            .disabled(!session.isConnected)

            LabeledField("ms") {
                TextField("1000", text: $session.pollIntervalStr)
                    .frame(width: 60)
            }
            .disabled(!session.autoPoll)
        }
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: - Status Bar

private struct StatusBar: View {
    @ObservedObject var session: ScanSession

    var body: some View {
        HStack {
            if session.isBusy {
                ProgressView().scaleEffect(0.5).frame(width: 16)
            }
            Text(session.statusMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            if session.readCount > 0 {
                Text("Reads: \(session.readCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Labeled field helper

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
