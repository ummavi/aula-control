import Foundation

/// Wireless report 13 framing. Payload includes the length byte for generated pages.
public enum WirelessPacket {
    public static func make(command: UInt8, total: UInt8 = 1, sequence: UInt8 = 0, payload: [UInt8] = []) -> [UInt8] {
        precondition(payload.count <= 15)
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x13
        bytes[1] = command
        bytes[2] = total
        bytes[3] = sequence
        bytes.replaceSubrange(4..<(4 + payload.count), with: payload)
        seal(&bytes)
        return bytes
    }
    public static func seal(_ bytes: inout [UInt8]) { bytes[19] = bytes.prefix(19).reduce(0, &+) }
    public static func valid(_ bytes: [UInt8]) -> Bool {
        bytes.count == 20 && bytes[0] == 0x13 && bytes[19] == bytes.prefix(19).reduce(0, &+)
    }
    public static func unpack(_ packets: [[UInt8]], command: UInt8) throws -> [UInt8] {
        guard let first = packets.first, valid(first), first[1] == command else {
            throw AulaError.message("The keyboard returned an invalid response.")
        }
        let count = Int(first[2])
        guard count > 0, count <= 64, packets.count == count else {
            throw AulaError.incompleteResponse(command: command, received: packets.count, expected: count)
        }
        let sorted = packets.sorted { $0[3] < $1[3] }
        var data: [UInt8] = []
        for (index, packet) in sorted.enumerated() {
            guard valid(packet), packet[1] == command, Int(packet[2]) == count,
                Int(packet[3]) == index, packet[4] <= 14
            else {
                throw AulaError.message("The keyboard returned inconsistent configuration packets.")
            }
            data += packet[5..<(5 + Int(packet[4]))]
        }
        return data
    }
}

/// Repeat the same page when its echo is lost, without skipping to later pages.
/// Closures let regression tests exercise packet loss without attached hardware.
enum WirelessWriter {
    static func write(
        _ packets: [[UInt8]], send: ([UInt8]) throws -> Void,
        receiveEcho: ([UInt8]) -> Bool, pause: () -> Void
    ) throws {
        for packet in packets {
            var acknowledged = false
            for _ in 0..<3 {
                try send(packet)
                if receiveEcho(packet) {
                    acknowledged = true
                    break
                }
                pause()
            }
            guard acknowledged else {
                throw AulaError.missingAcknowledgment(
                    command: packet[1], sequence: Int(packet[3]), count: Int(packet[2]))
            }
            pause()
        }
    }
}

/// Read-only requests can be repeated when a burst loses pages. Retain valid
/// pages between attempts, but discard the earlier attempt on any overlapping
/// data change or page-count change. Never fabricate or zero-fill missing data.
struct WirelessReadAssembly {
    let command: UInt8
    private(set) var pages: [Int: [UInt8]] = [:]
    private(set) var expectedCount = 0
    private func sameData(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        // Short final pages contain padding copied from earlier USB reports.
        // Only their declared payload belongs to the settings snapshot.
        lhs.prefix(5 + Int(lhs[4])).elementsEqual(rhs.prefix(5 + Int(rhs[4])))
    }
    mutating func merge(_ incoming: [[UInt8]]) throws -> [UInt8]? {
        guard let first = incoming.first else { return nil }
        guard WirelessPacket.valid(first) else { throw AulaError.message("The receiver returned an invalid response.") }
        let count = Int(first[2])
        guard (1...64).contains(count) else {
            throw AulaError.message("The receiver returned an unsupported response size.")
        }
        var current: [Int: [UInt8]] = [:]
        for page in incoming {
            guard WirelessPacket.valid(page), page[1] == command, Int(page[2]) == count,
                Int(page[3]) < count, page[4] <= 14
            else {
                throw AulaError.message("The receiver returned inconsistent configuration packets.")
            }
            let index = Int(page[3])
            if let duplicate = current[index], !sameData(duplicate, page) {
                throw AulaError.message("The receiver changed settings while sending a response. Retry the operation.")
            }
            current[index] = page
        }
        let changed =
            expectedCount != count
            || current.contains { index, page in
                if let earlier = pages[index] { return !sameData(earlier, page) }
                return false
            }
        if changed { pages = [:] }
        expectedCount = count
        pages.merge(current) { _, latest in latest }
        guard pages.count == expectedCount else { return nil }
        return try WirelessPacket.unpack(Array(pages.values), command: command)
    }
}
