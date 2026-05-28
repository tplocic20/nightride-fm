import Foundation
import Darwin

/// Minimal Discord IPC client: connects to the local `/tmp/discord-ipc-N`
/// Unix socket, handshakes, and pushes `SET_ACTIVITY` frames. Silent no-op
/// if Discord isn't running.
final class DiscordRPC {
    struct Activity {
        let details: String
        let state: String
        let startTimestamp: Date?
        let largeImage: String
        let largeText: String
    }

    private let clientID: String
    private let queue = DispatchQueue(label: "fm.nightride.discord-rpc", qos: .utility)
    private var fd: Int32 = -1
    private var handshakeDone = false

    init(clientID: String) {
        self.clientID = clientID
    }

    deinit { disconnect() }

    func update(activity: Activity?) {
        queue.async { [weak self] in self?.send(activity: activity) }
    }

    // MARK: – Connection lifecycle

    private func connect() {
        for i in 0..<10 {
            let path = "/tmp/discord-ipc-\(i)"
            let s = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { continue }

            // Don't kill the process if Discord closes the socket on us.
            var on: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = path.utf8CString
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                let buf = raw.bindMemory(to: CChar.self)
                let limit = min(bytes.count, buf.count)
                for i in 0..<limit { buf[i] = bytes[i] }
            }

            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            let r = withUnsafePointer(to: &addr) { p -> Int32 in
                p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(s, $0, size)
                }
            }
            if r == 0 {
                fd = s
                handshakeDone = false
                return
            }
            close(s)
        }
    }

    private func disconnect() {
        if fd >= 0 { close(fd); fd = -1 }
        handshakeDone = false
    }

    // MARK: – Frame writing

    private func send(activity: Activity?) {
        if fd < 0 { connect() }
        guard fd >= 0 else { return }

        if !handshakeDone {
            let handshake: [String: Any] = ["v": 1, "client_id": clientID]
            guard writeFrame(op: 0, payload: handshake) else { disconnect(); return }
            handshakeDone = true
        }

        var args: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier]
        if let a = activity {
            var act: [String: Any] = [
                "type": 2,
                "details": a.details,
                "state": a.state,
                "assets": [
                    "large_image": a.largeImage,
                    "large_text": a.largeText,
                ],
            ]
            if let start = a.startTimestamp {
                act["timestamps"] = ["start": Int(start.timeIntervalSince1970)]
            }
            args["activity"] = act
        } else {
            args["activity"] = NSNull()
        }
        let frame: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "nonce": UUID().uuidString,
            "args": args,
        ]
        if !writeFrame(op: 1, payload: frame) { disconnect() }
    }

    private func writeFrame(op: UInt32, payload: [String: Any]) -> Bool {
        guard let json = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return false
        }
        var packet = Data(capacity: 8 + json.count)
        var opLE = op.littleEndian
        var lenLE = UInt32(json.count).littleEndian
        packet.append(Data(bytes: &opLE,  count: 4))
        packet.append(Data(bytes: &lenLE, count: 4))
        packet.append(json)

        return packet.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            var off = 0
            while off < raw.count {
                let n = write(fd, base.advanced(by: off), raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }
}
