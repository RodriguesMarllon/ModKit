import Foundation
import SwiftUI

// MARK: - RegisterRow

struct RegisterRow: Identifiable {
    let id: UInt16  // equals address
    var address: UInt16
    var value: UInt16

    // Display helpers
    var addressLabel: String { "4\(String(format: "%04d", Int(address) + 1))" }
    var decLabel: String { "\(value)" }
    var hexLabel: String { String(format: "%04X", value) }
    var binLabel: String {
        let b = String(value, radix: 2)
        let padded = String(repeating: "0", count: 16 - b.count) + b
        let n0 = padded.prefix(4)
        let n1 = padded.dropFirst(4).prefix(4)
        let n2 = padded.dropFirst(8).prefix(4)
        let n3 = padded.dropFirst(12)
        return "\(n0) \(n1) \(n2) \(n3)"
    }

    init(address: UInt16, value: UInt16) {
        self.id = address
        self.address = address
        self.value = value
    }
}

// MARK: - ScanSession

@MainActor
final class ScanSession: ObservableObject {

    // Connection params — persisted via UserDefaults
    @Published var host = UserDefaults.standard.string(forKey: "mk.host") ?? "" {
        didSet { UserDefaults.standard.set(host, forKey: "mk.host") }
    }
    @Published var portStr = UserDefaults.standard.string(forKey: "mk.port") ?? "502" {
        didSet { UserDefaults.standard.set(portStr, forKey: "mk.port") }
    }
    @Published var unitID: Int = UserDefaults.standard.object(forKey: "mk.unitID") as? Int ?? 1 {
        didSet { UserDefaults.standard.set(unitID, forKey: "mk.unitID") }
    }

    // Scan params
    @Published var startAddrStr = "0"
    @Published var countStr = "50"
    @Published var functionCode: FunctionCode = .readHoldingRegisters

    // State
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var isBusy = false

    // Data
    @Published var rows: [RegisterRow] = []

    // Auto-poll
    @Published var autoPoll = false
    @Published var pollIntervalStr = "1000"

    // Status
    @Published var statusMessage = "Disconnected"
    @Published var readCount = 0

    // Write sheet
    @Published var writeTarget: RegisterRow?

    private let client = ModbusClient()
    private var pollTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?

    // MARK: Computed

    var port: UInt16 { UInt16(portStr) ?? 502 }
    var startAddr: UInt16 { UInt16(startAddrStr) ?? 0 }
    var count: Int { max(1, min(500, Int(countStr) ?? 50)) }
    var pollInterval: Int { max(200, Int(pollIntervalStr) ?? 1000) }

    // MARK: Connect

    func connect() {
        connectTask = Task { await doConnect() }
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        isConnecting = false
        statusMessage = "Cancelled"
    }

    func disconnect() {
        Task { await doDisconnect() }
    }

    private func doConnect() async {
        isConnecting = true
        statusMessage = "Connecting to \(host):\(port)..."
        do {
            try await client.connect(host: host, port: port)
            isConnected = true
            statusMessage = "Connected to \(host):\(port) — ready"
            await doScan()
        } catch is CancellationError {
            isConnected = false
            statusMessage = "Connection cancelled"
        } catch {
            isConnected = false
            statusMessage = "Error: \(error.localizedDescription)"
        }
        isConnecting = false
        connectTask = nil
    }

    private func doDisconnect() async {
        stopAutoPoll()
        autoPoll = false
        await client.disconnect()
        isConnected = false
        statusMessage = "Disconnected"
        rows = []
        readCount = 0
    }

    // MARK: Scan

    func scan() {
        Task { await doScan() }
    }

    func doScan() async {
        guard isConnected, !isBusy else { return }
        isBusy = true
        do {
            let vals = try await client.read(
                fc: functionCode,
                unitID: UInt8(unitID),
                startAddr: startAddr,
                count: count
            )
            rows = vals.enumerated().map { i, v in
                RegisterRow(address: UInt16(Int(startAddr) + i), value: v)
            }
            readCount += 1
            let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            statusMessage = "\(rows.count) registers read — \(t)  (polls: \(readCount))"
        } catch {
            statusMessage = "Read error: \(error.localizedDescription)"
            if case ModbusError.connectionFailed = error {
                isConnected = false
                stopAutoPoll()
            }
        }
        isBusy = false
    }

    // MARK: Auto-poll

    func toggleAutoPoll() {
        autoPoll ? stopAutoPoll() : startAutoPoll()
        autoPoll.toggle()
    }

    private func startAutoPoll() {
        stopAutoPoll()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.doScan()
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000)
            }
        }
    }

    private func stopAutoPoll() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Write

    func write(address: UInt16, value: UInt16) async throws {
        try await client.writeSingle(unitID: UInt8(unitID), address: address, value: value)
        if let idx = rows.firstIndex(where: { $0.address == address }) {
            rows[idx].value = value
        }
    }
}
