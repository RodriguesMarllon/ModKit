import Foundation
import Network

// MARK: - Errors

enum ModbusError: LocalizedError {
    case connectionFailed(String)
    case notConnected
    case exception(UInt8)
    case malformedResponse
    case requestTooLarge
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return "Connection failed: \(m)"
        case .notConnected:           return "Not connected"
        case .exception(let c):       return "Modbus exception 0x\(String(c, radix: 16, uppercase: true))"
        case .malformedResponse:      return "Malformed response"
        case .requestTooLarge:        return "Count exceeds Modbus limit (max 125 registers per request)"
        case .timeout:                return "Connection timed out"
        }
    }
}

// MARK: - Function codes

enum FunctionCode: UInt8 {
    case readCoils              = 0x01
    case readDiscreteInputs     = 0x02
    case readHoldingRegisters   = 0x03
    case readInputRegisters     = 0x04
    case writeSingleCoil        = 0x05
    case writeSingleRegister    = 0x06
    case writeMultipleRegisters = 0x10

    var label: String {
        switch self {
        case .readCoils:              return "Read Coils (FC01)"
        case .readDiscreteInputs:     return "Read Discrete Inputs (FC02)"
        case .readHoldingRegisters:   return "Read Holding Registers (FC03)"
        case .readInputRegisters:     return "Read Input Registers (FC04)"
        case .writeSingleCoil:        return "Write Single Coil (FC05)"
        case .writeSingleRegister:    return "Write Single Register (FC06)"
        case .writeMultipleRegisters: return "Write Multiple Registers (FC10)"
        }
    }

    var isReadable: Bool {
        switch self {
        case .readCoils, .readDiscreteInputs, .readHoldingRegisters, .readInputRegisters: return true
        default: return false
        }
    }
}

// MARK: - Client

/// Thread-safe Modbus TCP client. All methods are isolated to the actor queue.
actor ModbusClient {
    private var connection: NWConnection?
    private var tid: UInt16 = 0
    private(set) var connected = false

    // MARK: Connect / Disconnect

    func connect(host: String, port: UInt16, timeoutSeconds: Double = 8) async throws {
        if connected { await internalDisconnect() }

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ModbusError.connectionFailed("Invalid port \(port)")
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn

        // withTaskCancellationHandler: cancel button → conn.cancel() → stateHandler fires .cancelled
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                var resumed = false

                // Auto-timeout: if TCP handshake never completes (e.g. port filtered)
                let deadline = DispatchWorkItem {
                    guard !resumed else { return }
                    resumed = true
                    conn.cancel()
                    cont.resume(throwing: ModbusError.timeout)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: deadline)

                conn.stateUpdateHandler = { state in
                    deadline.cancel()
                    guard !resumed else { return }
                    switch state {
                    case .ready:
                        resumed = true
                        cont.resume()
                    case .failed(let err):
                        resumed = true
                        cont.resume(throwing: ModbusError.connectionFailed(err.localizedDescription))
                    case .cancelled:
                        resumed = true
                        cont.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                conn.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            conn.cancel()
        }
        connected = true
    }

    func disconnect() async {
        await internalDisconnect()
    }

    private func internalDisconnect() async {
        connection?.cancel()
        connection = nil
        connected = false
    }

    // MARK: Read

    /// Reads registers or coils in batches of up to 125 per request.
    func read(fc: FunctionCode, unitID: UInt8, startAddr: UInt16, count: Int) async throws -> [UInt16] {
        guard connected, let conn = connection else { throw ModbusError.notConnected }
        var results: [UInt16] = []
        var offset = 0
        while offset < count {
            let batch = min(125, count - offset)
            let addr = UInt16(Int(startAddr) + offset)
            let values = try await readBatch(conn: conn, fc: fc.rawValue, unitID: unitID,
                                             startAddr: addr, count: UInt16(batch))
            results.append(contentsOf: values)
            offset += batch
        }
        return results
    }

    private func readBatch(conn: NWConnection, fc: UInt8, unitID: UInt8,
                           startAddr: UInt16, count: UInt16) async throws -> [UInt16] {
        tid &+= 1
        var req = Data(count: 12)
        req[0] = UInt8(tid >> 8);   req[1] = UInt8(tid & 0xFF)
        req[2] = 0;                  req[3] = 0          // Protocol ID
        req[4] = 0;                  req[5] = 6          // Length
        req[6] = unitID;             req[7] = fc
        req[8] = UInt8(startAddr >> 8); req[9] = UInt8(startAddr & 0xFF)
        req[10] = UInt8(count >> 8); req[11] = UInt8(count & 0xFF)

        try await send(conn: conn, data: req)
        let body = try await receiveResponse(conn: conn)

        guard body.count >= 2 else { throw ModbusError.malformedResponse }
        if body[1] & 0x80 != 0 {
            throw ModbusError.exception(body.count > 2 ? body[2] : 0)
        }
        guard body.count >= 3 else { throw ModbusError.malformedResponse }
        let byteCount = Int(body[2])
        guard body.count >= 3 + byteCount else { throw ModbusError.malformedResponse }

        var values: [UInt16] = []
        for i in 0..<(byteCount / 2) {
            let hi = UInt16(body[3 + i * 2])
            let lo = UInt16(body[3 + i * 2 + 1])
            values.append(hi << 8 | lo)
        }
        return values
    }

    // MARK: Write

    func writeSingle(unitID: UInt8, address: UInt16, value: UInt16) async throws {
        guard connected, let conn = connection else { throw ModbusError.notConnected }
        tid &+= 1
        var req = Data(count: 12)
        req[0] = UInt8(tid >> 8); req[1] = UInt8(tid & 0xFF)
        req[4] = 0; req[5] = 6
        req[6] = unitID; req[7] = FunctionCode.writeSingleRegister.rawValue
        req[8] = UInt8(address >> 8); req[9] = UInt8(address & 0xFF)
        req[10] = UInt8(value >> 8); req[11] = UInt8(value & 0xFF)
        try await send(conn: conn, data: req)
        _ = try await receiveResponse(conn: conn)
    }

    func writeMultiple(unitID: UInt8, startAddr: UInt16, values: [UInt16]) async throws {
        guard connected, let conn = connection else { throw ModbusError.notConnected }
        let n = values.count
        let byteCount = n * 2
        let pduLen = 7 + byteCount
        tid &+= 1
        var req = Data(count: 6 + pduLen)
        req[0] = UInt8(tid >> 8); req[1] = UInt8(tid & 0xFF)
        req[4] = UInt8(pduLen >> 8); req[5] = UInt8(pduLen & 0xFF)
        req[6] = unitID; req[7] = FunctionCode.writeMultipleRegisters.rawValue
        req[8] = UInt8(startAddr >> 8); req[9] = UInt8(startAddr & 0xFF)
        req[10] = UInt8(n >> 8); req[11] = UInt8(n & 0xFF)
        req[12] = UInt8(byteCount)
        for (i, v) in values.enumerated() {
            req[13 + i * 2] = UInt8(v >> 8)
            req[14 + i * 2] = UInt8(v & 0xFF)
        }
        try await send(conn: conn, data: req)
        _ = try await receiveResponse(conn: conn)
    }

    // MARK: Transport helpers

    private func send(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err = err {
                    cont.resume(throwing: ModbusError.connectionFailed(err.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    /// Reads MBAP header (6 bytes) then body (length field bytes), returns the body.
    private func receiveResponse(conn: NWConnection) async throws -> Data {
        let header = try await receiveExact(conn: conn, count: 6)
        let bodyLen = Int(header[4]) << 8 | Int(header[5])
        guard bodyLen > 0 else { throw ModbusError.malformedResponse }
        return try await receiveExact(conn: conn, count: bodyLen)
    }

    private func receiveExact(conn: NWConnection, count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, err in
                if let err = err {
                    cont.resume(throwing: ModbusError.connectionFailed(err.localizedDescription))
                } else if let data, data.count >= count {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: ModbusError.malformedResponse)
                }
            }
        }
    }
}
