import Foundation
import Network

extension TidalDriftTestRunner {
    
    func testUDPPortBind() async -> (Bool, String) {
        await testPortBind(label: "UDP", params: .udp, port: 15904)
    }
    
    func testTCPPortBind() async -> (Bool, String) {
        await testPortBind(label: "TCP", params: .tcp, port: 15902)
    }
    
    private func testPortBind(label: String, params: NWParameters, port: UInt16) async -> (Bool, String) {
        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            
            let result = await withCheckedContinuation { (continuation: CheckedContinuation<NWListener.State, Never>) in
                var resumed = false
                listener.stateUpdateHandler = { state in
                    guard !resumed else { return }
                    switch state {
                    case .ready, .failed, .cancelled:
                        resumed = true
                        continuation.resume(returning: state)
                    default:
                        break
                    }
                }
                listener.start(queue: DispatchQueue(label: "test.\(label.lowercased()).bind"))
                
                // Timeout after 5 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: .cancelled)
                }
            }
            
            listener.cancel()
            
            if case .ready = result {
                return (true, "Successfully bound \(label) on port \(port)")
            }
            return (false, "\(label) listener reached state \(result) instead of ready on port \(port)")
        } catch {
            return (false, "Cannot bind \(label) port \(port): \(error.localizedDescription)")
        }
    }
    
    func testLoopbackTCPRoundtrip() async -> (Bool, String) {
        let testPort: UInt16 = 15910
        let testPayload = "TidalDrift-TCP-Test-\(UUID().uuidString)"
        var receivedData: String?
        
        // Start a listener
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: testPort)!)
        } catch {
            return (false, "Cannot create TCP listener: \(error.localizedDescription)")
        }
        
        let queue = DispatchQueue(label: "test.tcp.roundtrip")
        
        listener.newConnectionHandler = { conn in
            conn.start(queue: queue)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                if let data = data, let str = String(data: data, encoding: .utf8) {
                    receivedData = str
                    // Echo back
                    conn.send(content: data, completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                }
            }
        }
        listener.start(queue: queue)
        
        defer { listener.cancel() }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Connect and send
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: testPort)!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        var echoReceived: String?
        
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                conn.send(content: testPayload.data(using: .utf8), completion: .contentProcessed { _ in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        if let data = data { echoReceived = String(data: data, encoding: .utf8) }
                        conn.cancel()
                    }
                })
            }
        }
        conn.start(queue: queue)
        
        // Wait for roundtrip
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if echoReceived != nil { break }
        }
        
        if let echo = echoReceived, echo == testPayload {
            return (true, "TCP loopback echo: sent and received \(testPayload.count) bytes")
        }
        if receivedData != nil {
            return (false, "Server received data but client did not get echo back")
        }
        return (false, "TCP loopback roundtrip timed out")
    }
    
    func testLoopbackUDPRoundtrip() async -> (Bool, String) {
        let testPort: UInt16 = 15911
        let testPayload = "TidalDrift-UDP-Test-\(UUID().uuidString)"
        var received = false
        
        let listener: NWListener
        do {
            listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: testPort)!)
        } catch {
            return (false, "Cannot create UDP listener: \(error.localizedDescription)")
        }
        
        let queue = DispatchQueue(label: "test.udp.roundtrip")
        
        listener.newConnectionHandler = { conn in
            conn.start(queue: queue)
            conn.receiveMessage { data, _, _, _ in
                if let data = data, String(data: data, encoding: .utf8) == testPayload {
                    received = true
                }
                conn.cancel()
            }
        }
        listener.start(queue: queue)
        
        defer { listener.cancel() }
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // Send a UDP packet to ourselves
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: testPort)!)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                conn.send(content: testPayload.data(using: .utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
        conn.start(queue: queue)
        
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if received { break }
        }
        
        return (received,
                received ? "UDP loopback: sent and received \(testPayload.count) bytes"
                         : "UDP loopback roundtrip timed out")
    }
}
