import SwiftUI

struct WriteView: View {
    let row: RegisterRow
    @ObservedObject var session: ScanSession
    @Environment(\.dismiss) private var dismiss

    @State private var decStr = ""
    @State private var hexStr = ""
    @State private var errorMsg = ""
    @State private var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Write Register")
                        .font(.headline)
                    Text("\(row.addressLabel)  —  current: \(row.decLabel) (0x\(row.hexLabel))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 16)

            Divider()

            // Inputs
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decimal  (0 – 65535)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0", text: $decStr)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                            .onChange(of: decStr) { v in
                                if let n = UInt16(v) {
                                    hexStr = String(format: "%04X", n)
                                    errorMsg = ""
                                }
                            }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hex  (0000 – FFFF)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("0000", text: $hexStr)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                            .onChange(of: hexStr) { v in
                                if let n = UInt16(v.uppercased(), radix: 16) {
                                    decStr = "\(n)"
                                    errorMsg = ""
                                }
                            }
                    }
                }

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.escape)

                Button {
                    doWrite()
                } label: {
                    if isBusy {
                        ProgressView().scaleEffect(0.6).frame(width: 60)
                    } else {
                        Text("Write")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 360)
        .onAppear {
            decStr = row.decLabel
            hexStr = row.hexLabel
        }
    }

    private func doWrite() {
        guard let value = UInt16(decStr) else {
            errorMsg = "Enter a value between 0 and 65535"
            return
        }
        isBusy = true
        Task {
            do {
                try await session.write(address: row.address, value: value)
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isBusy = false
        }
    }
}
