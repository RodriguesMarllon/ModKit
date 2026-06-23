import Foundation
import SwiftUI

@MainActor
final class SimulatorSession: ObservableObject {

    // Config
    @Published var portStr = "502"
    @Published var isRunning = false
    @Published var errorMsg: String?

    // Live stats (updated by poll timer)
    @Published var registers: [UInt16] = Array(repeating: 0, count: 2000)
    @Published var readCount = 0
    @Published var writeCount = 0
    @Published var lastClient = "—"
    @Published var uptimeStr = "—"

    // UI state
    @Published var page = 0
    @Published var editTarget: SimRegister?

    let pageSize = 50
    var pageCount: Int { 2000 / pageSize }

    var port: UInt16 { UInt16(portStr) ?? 502 }

    var pageRegisters: [SimRegister] {
        let start = page * pageSize
        return (start..<min(start + pageSize, 2000)).map { i in
            SimRegister(index: i, value: registers[i])
        }
    }

    private let server = ModbusServer()
    private var pollTask: Task<Void, Never>?

    // MARK: Start / Stop

    func start() {
        Task { await doStart() }
    }

    func stop() {
        Task { await doStop() }
    }

    private func doStart() async {
        errorMsg = nil
        do {
            try await server.start(port: port)
            isRunning = true
            startPolling()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func doStop() async {
        stopPolling()
        await server.stop()
        isRunning = false
        uptimeStr = "—"
        readCount = 0
        writeCount = 0
        lastClient = "—"
    }

    // MARK: Register ops

    func setRegister(index: Int, value: UInt16) {
        registers[index] = value
        Task { await server.setRegister(index, value: value) }
    }

    func resetAll() {
        registers = Array(repeating: 0, count: 2000)
        Task { await server.resetAll() }
    }

    // MARK: Polling

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        let snap = await server.snapshot()
        registers = snap.registers
        readCount = snap.readCount
        writeCount = snap.writeCount
        lastClient = snap.lastClient
        uptimeStr = formatUptime(snap.uptime)
    }

    private func formatUptime(_ t: TimeInterval) -> String {
        guard t > 0 else { return "—" }
        let h = Int(t) / 3600
        let m = Int(t) % 3600 / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - SimRegister

struct SimRegister: Identifiable {
    let index: Int
    var value: UInt16

    var id: Int { index }
    var addressLabel: String { "4\(String(format: "%04d", index + 1))" }
    var hexLabel: String { String(format: "%04X", value) }
}
