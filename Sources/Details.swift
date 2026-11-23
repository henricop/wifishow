import Foundation
import CoreWLAN
import Darwin

// MARK: - Full portrait of the connected interface
//
// A scan returns little about neighboring networks, but CoreWLAN exposes much
// more about the connected one: transmit rate, power, country code, PHY mode,
// adapter MAC. This screen gathers all of it in one place.

struct InterfaceDetails {
    var interfaceName   = "-"
    var hardwareAddress = "-"
    var ssid            = "-"
    var bssid           = "-"
    var rssi            = 0
    var noise           = 0
    var transmitRate    = 0.0
    var transmitPower   = 0
    var countryCode     = "-"
    var security        = "-"
    var phyMode         = "-"
    var channel         = 0
    var band: Band?     = nil
    var width: CWChannelWidth = .widthUnknown
    var powerOn         = false
    var serviceActive   = false
    var ipv4            = "-"
    var ipv6            = "-"
    /// Set when a scan of this BSSID learned a width the interface enum cannot
    /// report (320 MHz, from the EHT Operation element).
    var scannedCarrier: ResolvedCarrier?

    var snr: Int { noise != 0 ? rssi - noise : 0 }

    var carrier: ResolvedCarrier {
        if let scannedCarrier { return scannedCarrier }
        guard let b = band, channel > 0 else { return .unknown }
        return ChannelPlan.resolve(channel: channel, band: b, width: width,
                                   informationElements: nil)
    }

    /// Prefer the scan's placement when it is a 320 MHz network. The interface's
    /// own `CWChannel` cannot name 320 MHz or which of 320-1 / 320-2 is in use;
    /// the beacon captured during the scan can.
    func applying(scanned: WifiNetwork?) -> InterfaceDetails {
        guard let scanned,
              let interfaceBand = band,
              channel > 0,
              scanned.channel == channel,
              scanned.band.rawValue == interfaceBand.rawValue,
              scanned.carrier.widthMHz == 320,
              !bssid.isEmpty, !scanned.bssid.isEmpty,
              scanned.bssid.lowercased() == bssid.lowercased()
        else { return self }
        var copy = self
        copy.scannedCarrier = scanned.carrier
        return copy
    }

    static func capture() -> InterfaceDetails {
        var d = InterfaceDetails()
        guard let i = CWWiFiClient.shared().interface() else { return d }

        d.interfaceName   = i.interfaceName ?? "-"
        d.hardwareAddress = i.hardwareAddress() ?? "-"
        d.ssid            = i.ssid() ?? "-"
        d.bssid           = i.bssid() ?? "-"
        d.rssi            = i.rssiValue()
        d.noise           = i.noiseMeasurement()
        d.transmitRate    = i.transmitRate()
        d.transmitPower   = i.transmitPower()
        d.countryCode     = i.countryCode() ?? "-"
        d.powerOn         = i.powerOn()
        d.serviceActive   = i.serviceActive()
        d.phyMode         = Describe.phy(i.activePHYMode())
        d.security        = Describe.interfaceSecurity(i.security())

        if let ch = i.wlanChannel() {
            d.channel = ch.channelNumber
            d.band    = Band(rawValue: ch.channelBand.rawValue)
            d.width   = ch.channelWidth
        }

        let addrs = Self.addresses(for: d.interfaceName)
        d.ipv4 = addrs.v4 ?? "-"
        d.ipv6 = addrs.v6 ?? "-"
        return d
    }

    /// Local IP addresses of the interface, via getifaddrs.
    private static func addresses(for iface: String) -> (v4: String?, v6: String?) {
        var v4: String?, v6: String?
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return (nil, nil) }
        defer { freeifaddrs(head) }

        for ptr in sequence(first: start, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let name = ifa.ifa_name, String(cString: name) == iface,
                  let sa = ifa.ifa_addr else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == UInt8(AF_INET)
                                ? MemoryLayout<sockaddr_in>.size
                                : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(sa, len, &buf, socklen_t(buf.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let addr = String(cString: buf)

            if family == UInt8(AF_INET) {
                v4 = addr
            } else if v6 == nil, !addr.hasPrefix("fe80") {   // skip link-local
                v6 = addr
            }
        }
        return (v4, v6)
    }
}

// MARK: - Explained item
//
// Every metric ships with an explanation of what it means. The goal is that
// someone without a networking background can read the whole screen without
// looking anything up elsewhere.

struct DetailItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let explanation: String
}

struct DetailCategory: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let items: [DetailItem]
}

enum DetailsBuilder {

    static func categories(_ d: InterfaceDetails) -> [DetailCategory] {
        [
            DetailCategory(title: "Identity", icon: "tag", items: [
                DetailItem(key: "Network name (SSID)", value: d.ssid,
                           explanation: "Service Set Identifier — the name the router advertises. Several networks can share the same name; what tells them apart is the BSSID."),
                DetailItem(key: "BSSID", value: d.bssid,
                           explanation: "Basic Service Set Identifier — the MAC address of the access point you are connected to. On mesh networks it changes when you roam between nodes."),
                DetailItem(key: "Interface", value: d.interfaceName,
                           explanation: "Name of the Wi-Fi adapter as the system sees it. On Macs this is almost always en0 or en1."),
                DetailItem(key: "Adapter MAC", value: d.hardwareAddress,
                           explanation: "Physical address of this Mac's Wi-Fi card. macOS may present a randomized address to each network for privacy."),
                DetailItem(key: "IPv4 address", value: d.ipv4,
                           explanation: "Address identifying this Mac on the local network. Usually assigned by the router over DHCP."),
                DetailItem(key: "IPv6 address", value: d.ipv6,
                           explanation: "Global IPv6 address, when your provider offers one. Link-local addresses (fe80::) are omitted."),
            ]),

            DetailCategory(title: "Signal", icon: "antenna.radiowaves.left.and.right", items: [
                DetailItem(key: "RSSI", value: "\(d.rssi) dBm",
                           explanation: "Received Signal Strength Indicator — how strong the incoming signal is. It is negative: the closer to zero, the better. Above -55 is excellent; below -75 it starts to hurt."),
                DetailItem(key: "Noise", value: d.noise != 0 ? "\(d.noise) dBm" : "-",
                           explanation: "Background energy on the same band, coming from other networks, microwaves, Bluetooth. The more negative, the cleaner the environment."),
                DetailItem(key: "SNR", value: d.snr != 0 ? "\(d.snr) dB" : "-",
                           explanation: "Signal-to-Noise Ratio — the gap between signal and noise, and the number that matters most. Above 40 dB is great; below 20 dB throughput drops sharply."),
                DetailItem(key: "Quality", value: qualityLabel(d.rssi),
                           explanation: "Plain-language reading of the RSSI value."),
                DetailItem(key: "Transmit rate", value: d.transmitRate > 0 ? "\(Int(d.transmitRate)) Mbps" : "-",
                           explanation: "Rate currently negotiated on the radio — this is not your internet speed. It is the ceiling of the link between this Mac and the router."),
                DetailItem(key: "Transmit power", value: d.transmitPower > 0 ? "\(d.transmitPower)" : "-",
                           explanation: "Raw power value reported by the driver. Apple documents it as mW, but on modern Macs the number does not match real milliwatts — the legal limit is around 100 mW. Use it to compare relative changes, not as an absolute measurement."),
            ]),

            DetailCategory(title: "Channel and frequency", icon: "waveform", items: channelItems(d)),

            DetailCategory(title: "Configuration", icon: "gearshape", items: [
                DetailItem(key: "Security", value: d.security,
                           explanation: "Encryption protocol in use. WPA3 is current; WPA2 is still safe; WEP and open networks protect nothing."),
                DetailItem(key: "PHY mode", value: d.phyMode,
                           explanation: "Generation of the 802.11 standard in use. Wi-Fi 6 (ax) and newer handle many simultaneous devices far better."),
                DetailItem(key: "Country code", value: d.countryCode,
                           explanation: "Country per ISO 3166-1, detected from the router. It determines which channels and power levels are legally allowed."),
                DetailItem(key: "Radio on", value: d.powerOn ? "Yes" : "No",
                           explanation: "Whether this Mac's Wi-Fi radio is powered on."),
                DetailItem(key: "Service active", value: d.serviceActive ? "Yes" : "No",
                           explanation: "Whether the Wi-Fi interface is enabled in the system's network settings."),
            ]),
        ]
    }

    private static func channelItems(_ d: InterfaceDetails) -> [DetailItem] {
        let carrier = d.carrier
        var items = [
            DetailItem(key: "Channel", value: d.channel > 0 ? "\(d.channel)" : "-",
                       explanation: "Primary channel advertised by the router. On wide channels the carrier occupies a larger block, centered somewhere else."),
            DetailItem(key: "Band", value: d.band?.label ?? "-",
                       explanation: "2.4 GHz reaches farther and passes through walls, but it is crowded. 5 GHz is faster and cleaner with shorter range. 6 GHz is the cleanest and the shortest."),
            DetailItem(key: "Channel width", value: carrier.widthText,
                       explanation: "How much spectrum the network occupies. More width means more speed, but a higher chance of colliding with neighbors. Wi-Fi 7 can use 320 MHz. macOS does not report that width on CWChannel (the enum stops at 160); when the beacon includes an EHT Operation element, that is what this value follows."),
            DetailItem(key: "Center frequency", value: carrier.centerText,
                       explanation: "Real center of the carrier, already accounting for width — it is not the primary channel's frequency when the channel is wide. On 6 GHz, 320 MHz has two overlapping plans (320-1 and 320-2). When the beacon names the center, this is that frequency. When it does not, and the primary channel sits in both plans, the value is marked ambiguous and both blocks are drawn on the chart."),
            DetailItem(key: "Occupied range", value: carrier.rangeText,
                       explanation: "Frequency span this network actually occupies. Networks whose spans overlap interfere with each other. An ambiguous 320 MHz network lists both candidate spans."),
        ]
        if carrier.widthMHz == 320 {
            items.append(DetailItem(
                key: "320 MHz block",
                value: carrier.blockText,
                explanation: "Which 320 MHz channelisation the network uses. 320-1 is centered on channels 31, 95 or 159. 320-2 is centered on 63, 127 or 191. The two plans overlap, so the primary channel alone cannot tell them apart. The beacon's EHT Operation element (CCFS1) names the center. Ambiguous means that element was missing or did not name a center, and the primary channel belongs to both plans."
            ))
        }
        return items
    }

    private static func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case 0:             return "-"
        case (-55)...:      return "Excellent"
        case (-67)..<(-55): return "Good"
        case (-75)..<(-67): return "Fair"
        default:            return "Poor"
        }
    }
}
