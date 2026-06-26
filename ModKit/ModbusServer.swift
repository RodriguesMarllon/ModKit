import Foundation
import Network

// MARK: - ModbusServer

actor ModbusServer {

    struct Snapshot {
        var registers: [UInt16]
        var readCount: Int
        var writeCount: Int
        var lastClient: String
        var uptime: TimeInterval
    }

    private var listener: NWListener?
    private(set) var running = false
    private var registers = [UInt16](repeating: 0, count: 2000)
    private var readCount = 0
    private var writeCount = 0
    private var lastClient = "—"
    private var startTime: Date?

    // MARK: Start / Stop

    func start(port: UInt16) throws {
        guard !running else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ModbusError.connectionFailed("Invalid port \(port)")
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let ln = try NWListener(using: params, on: nwPort)
        self.listener = ln

        ln.newConnectionHandler = { [weak self] conn in
            guard let server = self else { return }
            Task { await server.accept(conn) }
        }
        ln.start(queue: .global(qos: .userInitiated))
        running = true
        startTime = Date()
        readCount = 0
        writeCount = 0
        lastClient = "—"
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
        startTime = nil
    }

    func setRegister(_ address: Int, value: UInt16) {
        guard (0..<registers.count).contains(address) else { return }
        registers[address] = value
    }

    func resetAll() {
        registers = [UInt16](repeating: 0, count: 2000)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            registers: registers,
            readCount: readCount,
            writeCount: writeCount,
            lastClient: lastClient,
            uptime: startTime.map { Date().timeIntervalSince($0) } ?? 0
        )
    }

    // MARK: Connection handling

    private func accept(_ conn: NWConnection) {
        lastClient = "\(conn.endpoint)"
        conn.start(queue: .global(qos: .userInitiated))
        receiveLoop(conn: conn, buffer: Data())
    }

    private func receiveLoop(conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] chunk, _, done, err in
            guard let server = self else { return }
            if err != nil || done { conn.cancel(); return }

            var buf = buffer
            if let chunk { buf.append(chunk) }

            Task {
                let (remaining, responses) = await server.drain(buf)
                for r in responses {
                    conn.send(content: r, completion: .idempotent)
                }
                await server.receiveLoop(conn: conn, buffer: remaining)
            }
        }
    }

    // Extract and process complete MBAP frames from buffer
    private func drain(_ buffer: Data) -> (Data, [Data]) {
        var buf = buffer
        var responses: [Data] = []
        while buf.count >= 6 {
            let length = Int(buf[4]) << 8 | Int(buf[5])
            let total = 6 + length
            guard buf.count >= total else { break }
            if let resp = processFrame(Data(buf.prefix(total))) {
                responses.append(resp)
            }
            buf = Data(buf.dropFirst(total))
        }
        return (buf, responses)
    }

    // MARK: Modbus frame processing

    private func processFrame(_ data: Data) -> Data? {
        guard data.count >= 8 else { return nil }

        let tid  = Data(data[0..<2])
        let uid  = data[6]
        let fc   = data[7]

        // Build MBAP response wrapper
        func mbap(_ payload: Data) -> Data {
            var r = tid
            r.append(contentsOf: [0, 0])
            let l = UInt16(1 + payload.count)
            r.append(UInt8(l >> 8)); r.append(UInt8(l & 0xFF))
            r.append(uid)
            r.append(contentsOf: payload)
            return r
        }
        func exception(_ code: UInt8) -> Data { mbap(Data([fc | 0x80, code])) }

        switch fc {

        case 0x03: // Read Holding Registers
            guard data.count >= 12 else { return nil }
            let start = Int(data[8]) << 8 | Int(data[9])
            let qty   = Int(data[10]) << 8 | Int(data[11])
            guard qty >= 1, qty <= 125 else { return exception(0x03) }
            guard start + qty <= registers.count else { return exception(0x02) }
            var payload = Data([fc, UInt8(qty * 2)])
            for i in 0..<qty {
                let v = registers[start + i]
                payload.append(UInt8(v >> 8)); payload.append(UInt8(v & 0xFF))
            }
            readCount += 1
            return mbap(payload)

        case 0x06: // Write Single Register
            guard data.count >= 12 else { return nil }
            let addr = Int(data[8]) << 8 | Int(data[9])
            let val  = UInt16(data[10]) << 8 | UInt16(data[11])
            guard addr < registers.count else { return exception(0x02) }
            registers[addr] = val
            writeCount += 1
            return Data(data.prefix(12))

        case 0x10: // Write Multiple Registers
            guard data.count >= 13 else { return nil }
            let start     = Int(data[8]) << 8 | Int(data[9])
            let qty       = Int(data[10]) << 8 | Int(data[11])
            let byteCount = Int(data[12])
            guard byteCount == qty * 2, data.count >= 13 + byteCount else { return exception(0x03) }
            guard start + qty <= registers.count else { return exception(0x02) }
            for i in 0..<qty {
                let hi = UInt16(data[13 + i * 2])
                let lo = UInt16(data[14 + i * 2])
                registers[start + i] = hi << 8 | lo
            }
            writeCount += 1
            var payload = Data([fc])
            payload.append(contentsOf: data[8..<12])
            return mbap(payload)

        default:
            return exception(0x01)
        }
    }
}
