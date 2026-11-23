import Foundation
import Observation
import CoreWLAN
import CoreLocation
import AppKit

// MARK: - Location permission
//
// Since macOS 14, CoreWLAN returns ssid/bssid == nil without location
// authorization. Without this gate the app would just show an empty list
// and never explain why.

@Observable
@MainActor
final class LocationGate: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        status == .authorizedAlways || status == .authorized
    }

    var message: String {
        switch status {
        case .notDetermined: return "Waiting for location authorization..."
        case .restricted:    return "Location is restricted by system policy."
        case .denied:        return "Location denied. Without it macOS hides SSID and BSSID."
        default:             return "Location authorized."
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        Task { @MainActor in self.status = s }
    }

    func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!
        NSWorkspace.shared.open(url)
    }
}

// MARK: - History sample

struct SignalSample: Identifiable {
    let id = UUID()
    let time: Date
    let rssi: Int
    let snr: Int
}

// MARK: - Scanner

@Observable
@MainActor
final class WifiScanner {

    // Results
    private(set) var networks: [WifiNetwork] = []
    private(set) var connected: WifiNetwork?
    private(set) var noiseFloor: Int = -92
    private(set) var interfaceName: String = "-"
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var errorText: String?
    private(set) var powerOn = true

    // Signal history for the connected network
    private(set) var history: [SignalSample] = []
    private let historyLimit = 720   // ~12 min at 1 sample/s

    // Control
    var interval: TimeInterval = 5
    private var scanTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?

    func start() {
        guard scanTask == nil else { return }

        // Slow loop: full scan of neighboring networks (blocking, ~2-4s).
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.scanOnce()
                let secs = await MainActor.run { self?.interval ?? 5 }
                try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            }
        }

        // Fast loop: connected-interface telemetry, 1/s, with no scan cost.
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleConnected()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        scanTask?.cancel();    scanTask = nil
        monitorTask?.cancel(); monitorTask = nil
    }

    func scanNow() {
        Task { await scanOnce() }
    }

    func clearHistory() { history.removeAll() }

    // MARK: Fast telemetry of the connected interface

    private func sampleConnected() async {
        let snapshot = await Task.detached(priority: .utility) { () -> (String, Int, Int, Bool)? in
            guard let i = CWWiFiClient.shared().interface() else { return nil }
            return (i.interfaceName ?? "-", i.rssiValue(), i.noiseMeasurement(), i.powerOn())
        }.value

        guard let (name, rssi, noise, power) = snapshot else { return }
        interfaceName = name
        powerOn = power
        if noise != 0 { noiseFloor = noise }
        guard power, rssi != 0 else { return }

        history.append(SignalSample(time: Date(), rssi: rssi, snr: rssi - (noise != 0 ? noise : noiseFloor)))
        if history.count > historyLimit { history.removeFirst(history.count - historyLimit) }
    }

    // MARK: Full scan

    private func scanOnce() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let result = await Task.detached(priority: .userInitiated) { () -> Result<([WifiNetwork], String?), Error> in
            guard let iface = CWWiFiClient.shared().interface() else {
                return .failure(ScanError.noInterface)
            }
            let currentBSSID = iface.bssid()
            do {
                let found = try iface.scanForNetworks(withSSID: nil)
                let mapped: [WifiNetwork] = found.compactMap { n in
                    guard let ch = n.wlanChannel,
                          let band = Band(rawValue: ch.channelBand.rawValue) else { return nil }
                    let bssid = n.bssid ?? ""
                    return WifiNetwork(
                        ssid: n.ssid ?? "",
                        bssid: bssid,
                        rssi: n.rssiValue,
                        noise: n.noiseMeasurement,
                        channel: ch.channelNumber,
                        band: band,
                        width: ch.channelWidth,
                        security: Describe.security(n),
                        phyMode: "-",
                        isConnected: !bssid.isEmpty && bssid == currentBSSID,
                        // Beacon IEs. This is how a 320 MHz BSS tells us 320-1
                        // from 320-2; CWChannelWidth cannot. Nil without location
                        // permission, same gate as SSID.
                        informationElements: n.informationElementData
                    )
                }
                return .success((mapped, currentBSSID))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let (list, _)):
            networks = list.sorted { $0.rssi > $1.rssi }
            connected = list.first(where: { $0.isConnected })
            errorText = list.isEmpty ? "No networks found." : nil
            lastScan = Date()
        case .failure(let err):
            errorText = (err as? ScanError)?.text ?? err.localizedDescription
        }
    }

    // MARK: Derived

    func networks(in band: Band) -> [WifiNetwork] {
        networks.filter { $0.band == band }
    }

    func bandCounts() -> [Band: Int] {
        Dictionary(grouping: networks, by: \.band).mapValues(\.count)
    }

    /// Per-channel occupancy: how many networks and the strongest signal on each.
    func congestion(in band: Band) -> [(channel: Int, count: Int, bestRSSI: Int)] {
        Dictionary(grouping: networks(in: band), by: \.channel)
            .map { (ch, nets) in
                (channel: ch, count: nets.count, bestRSSI: nets.map(\.rssi).max() ?? -100)
            }
            .sorted { $0.channel < $1.channel }
    }

    /// Recommended 2.4 GHz channels: only 1, 6 and 11 do not overlap.
    func recommended24() -> [(channel: Int, score: Int)] {
        [1, 6, 11].map { ch in
            // Proximity weighting: channels within +-4 still interfere.
            let score = networks(in: .ghz24).reduce(0) { acc, n in
                let dist = abs(n.channel - ch)
                guard dist <= 4 else { return acc }
                let weight = max(0, 5 - dist)
                return acc + weight * max(0, n.rssi + 100)
            }
            return (ch, score)
        }.sorted { $0.score < $1.score }
    }
}

enum ScanError: Error {
    case noInterface
    var text: String {
        switch self {
        case .noInterface: return "No Wi-Fi interface found on this Mac."
        }
    }
}
