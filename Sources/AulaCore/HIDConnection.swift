import Foundation
import IOKit.hid

private final class InputReports {
    let condition = NSCondition()
    let trace = ProcessInfo.processInfo.environment["AULA_TRACE_HID"] == "1"
    var inbox: [[UInt8]] = []
    var count = 0
    var battery: Int?
}

/// Send commands serially. Input delivery runs independently on a dedicated
/// dispatch queue so a synchronous USB write cannot starve its own responses.
/// Only vendor report 0x13 is retained; normal input reports are discarded.
/// Callers must serialize reads and writes; this type does not arbitrate concurrent operations.
public final class HIDConnection {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private let inputQueue = DispatchQueue(label: "app.aula-control.hid.input", qos: .userInteractive)
    private let reports = InputReports()
    private let cancelled = DispatchSemaphore(value: 0)
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private let trace = ProcessInfo.processInfo.environment["AULA_TRACE_HID"] == "1"
    public var receivedCount: Int {
        reports.condition.lock()
        defer { reports.condition.unlock() }
        return reports.count
    }
    public private(set) var sentCount = 0
    public var reportedBattery: Int? {
        reports.condition.lock()
        defer { reports.condition.unlock() }
        return reports.battery
    }

    public init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey: 0x3554, kIOHIDProductIDKey: 0xFA09,
                kIOHIDPrimaryUsagePageKey: 0xFF02,
            ] as CFDictionary)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            buffer.deallocate()
            throw Self.accessError(result)
        }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        guard devices.count == 1, let found = devices.first else {
            IOHIDManagerClose(manager, 0)
            buffer.deallocate()
            throw AulaError.message(
                devices.isEmpty
                    ? "Connect the keyboard's 2.4 GHz USB receiver, switch the keyboard to 2.4G, then reconnect."
                    : "More than one matching receiver is connected. Leave only the AULA receiver connected.")
        }
        device = found
        // A palette arrives as 35 reports in one burst, alongside typing input.
        // Configure the IOHIDLib queue before registering its report callback.
        // These are per-client settings, not keyboard firmware configuration.
        IOHIDDeviceSetProperty(device, kIOHIDMaxReportBufferCountKey as CFString, 256 as CFNumber)
        IOHIDDeviceSetProperty(device, kIOHIDReportBufferEntrySizeKey as CFString, 64 as CFNumber)
        let opened = IOHIDDeviceOpen(device, 0)  // Never seize normal keyboard input.
        guard opened == kIOReturnSuccess else {
            IOHIDManagerClose(manager, 0)
            buffer.deallocate()
            throw Self.accessError(opened)
        }
        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, 64,
            { context, result, _, _, id, report, length in
                guard let context, result == kIOReturnSuccess, id == 0x13, length == 20 else { return }
                let owner = Unmanaged<InputReports>.fromOpaque(context).takeUnretainedValue()
                let packet = Array(UnsafeBufferPointer(start: report, count: length))
                if owner.trace {
                    fputs("RX \(packet.map { String(format: "%02X", $0) }.joined(separator: " "))\n", stderr)
                }
                guard WirelessPacket.valid(packet) else { return }
                owner.condition.lock()
                defer { owner.condition.unlock() }
                if packet[1] == 0x0A, packet[4] == 4, packet[7] == 1, packet[6] <= 100 {
                    owner.battery = Int(packet[6])
                }
                owner.count += 1
                if owner.inbox.count < 256 { owner.inbox.append(packet) }
                owner.condition.signal()
            }, Unmanaged.passUnretained(reports).toOpaque())
        IOHIDDeviceSetDispatchQueue(device, inputQueue)
        let completion = cancelled
        IOHIDDeviceSetCancelHandler(device) { completion.signal() }
        IOHIDDeviceActivate(device)
    }

    deinit {
        IOHIDDeviceCancel(device)
        // The cancel handler runs after all input callbacks finish. Keep their
        // context and buffer alive until then, without blocking the input queue.
        cancelled.wait()
        IOHIDDeviceClose(device, 0)
        IOHIDManagerClose(manager, 0)
        buffer.deallocate()
    }

    private static func accessError(_ code: IOReturn) -> AulaError {
        .message(
            String(
                format:
                    "macOS could not open the receiver (0x%08X). If macOS requests Input Monitoring access, enable AULA Control in System Settings → Privacy & Security → Input Monitoring, then reopen the app.",
                UInt32(bitPattern: code)))
    }
    private func send(_ packet: [UInt8]) throws {
        if trace { fputs("TX \(packet.map { String(format: "%02X", $0) }.joined(separator: " "))\n", stderr) }
        guard WirelessPacket.valid(packet) else { throw AulaError.message("Refused to send an invalid packet.") }
        let result = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x13, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw Self.accessError(result) }
        sentCount += 1
    }
    private func next(until deadline: Date, matching predicate: ([UInt8]) -> Bool) -> [UInt8]? {
        reports.condition.lock()
        defer { reports.condition.unlock() }
        while true {
            if let index = reports.inbox.firstIndex(where: predicate) { return reports.inbox.remove(at: index) }
            guard Date() < deadline, reports.condition.wait(until: deadline) else { return nil }
        }
    }
    private func discardPending() {
        reports.condition.lock()
        reports.inbox.removeAll()
        reports.condition.unlock()
    }
    public func read(command: UInt8, responseCommand: UInt8? = nil) throws -> [UInt8] {
        let response = responseCommand ?? command
        var assembly = WirelessReadAssembly(command: response)
        for _ in 0..<6 {
            let incoming = try readAttempt(command: command, responseCommand: response)
            if let result = try assembly.merge(incoming) { return result }
        }
        if assembly.expectedCount > 0 {
            throw AulaError.incompleteResponse(
                command: command, received: assembly.pages.count, expected: assembly.expectedCount)
        }
        throw AulaError.noResponse(command: command)
    }
    private func readAttempt(command: UInt8, responseCommand: UInt8) throws -> [[UInt8]] {
        Thread.sleep(forTimeInterval: 0.03)
        discardPending()
        try send(WirelessPacket.make(command: command))
        guard let first = next(until: Date().addingTimeInterval(1.5), matching: { $0[1] == responseCommand }) else {
            return []
        }
        let count = Int(first[2])
        guard (1...64).contains(count) else {
            throw AulaError.message("The receiver returned an unsupported response size.")
        }
        var pages = [first]
        var indices: Set<UInt8> = [first[3]]
        let deadline = Date().addingTimeInterval(1)
        while indices.count < count {
            let quietDeadline = min(deadline, Date().addingTimeInterval(0.08))
            guard let page = next(until: quietDeadline, matching: { $0[1] == responseCommand }) else { break }
            pages.append(page)
            indices.insert(page[3])
            if Date() >= deadline { break }
        }
        return pages
    }
    public func write(_ packets: [[UInt8]]) throws {
        discardPending()
        try WirelessWriter.write(
            packets, send: { try self.send($0) },
            receiveEcho: { packet in
                self.next(
                    until: Date().addingTimeInterval(0.7),
                    matching: {
                        // Match the full payload rather than accepting an unrelated
                        // report with a similar header as an acknowledgment.
                        $0 == packet
                    }) != nil
            },
            pause: {
                Thread.sleep(forTimeInterval: 0.02)
            })
    }
}
