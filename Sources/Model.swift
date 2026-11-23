import Foundation
import CoreWLAN

// MARK: - Band

enum Band: Int, CaseIterable, Identifiable, Sendable {
    case ghz24 = 1
    case ghz5  = 2
    case ghz6  = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .ghz24: return "2.4 GHz"
        case .ghz5:  return "5 GHz"
        case .ghz6:  return "6 GHz"
        }
    }

    /// Frequency range (MHz) used as the chart domain.
    var range: ClosedRange<Double> {
        switch self {
        case .ghz24: return 2400...2500
        case .ghz5:  return 5150...5895
        case .ghz6:  return 5925...7125
        }
    }

    /// Channels that get a tick on the X axis.
    var tickChannels: [Int] {
        switch self {
        case .ghz24: return Array(1...14)
        case .ghz5:  return [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112,
                             116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165]
        case .ghz6:  return stride(from: 1, through: 233, by: 16).map { $0 }
        }
    }
}

// MARK: - Channel plan

enum ChannelPlan {

    /// Center frequency (MHz) of a 20 MHz primary channel.
    static func centerFrequency(channel ch: Int, band: Band) -> Double {
        switch band {
        case .ghz24:
            if ch == 14 { return 2484 }
            return 2407 + Double(ch) * 5
        case .ghz5:
            return 5000 + Double(ch) * 5
        case .ghz6:
            if ch == 2 { return 5935 }
            return 5950 + Double(ch) * 5
        }
    }

    /// Width in MHz from the CoreWLAN enum.
    ///
    /// `CWChannelWidth` is still only unknown / 20 / 40 / 80 / 160 (raw values
    /// 0...4). There is no 320 MHz case, including on macOS 26.5.1. Unknown and
    /// any unrecognized raw value keep the historical 20 MHz fallback so older
    /// charts do not move; 320 MHz is decided in `resolve`, from the beacon.
    static func widthMHz(_ w: CWChannelWidth) -> Double {
        switch w {
        case .width20MHz:  return 20
        case .width40MHz:  return 40
        case .width80MHz:  return 80
        case .width160MHz: return 160
        default:           return 20
        }
    }

    /// CoreWLAN width when it is one of the four widths the enum can actually
    /// name. Unknown (0) and anything newer return nil instead of pretending
    /// to be 20 MHz — callers that still want the old fallback use `widthMHz`.
    static func knownWidthMHz(_ w: CWChannelWidth) -> Double? {
        switch w.rawValue {
        case 1: return 20
        case 2: return 40
        case 3: return 80
        case 4: return 160
        default: return nil
        }
    }

    // Canonical 5 GHz blocks: CoreWLAN reports the PRIMARY channel, but the
    // carrier occupies the whole block, centered somewhere else. Without this
    // the chart draws the network in the wrong place.
    private static let blocks5GHz40: [[Int]] = [
        [36, 40], [44, 48], [52, 56], [60, 64],
        [100, 104], [108, 112], [116, 120], [124, 128],
        [132, 136], [140, 144], [149, 153], [157, 161],
    ]
    private static let blocks5GHz80: [[Int]] = [
        [36, 40, 44, 48], [52, 56, 60, 64],
        [100, 104, 108, 112], [116, 120, 124, 128],
        [132, 136, 140, 144], [149, 153, 157, 161],
    ]
    private static let blocks5GHz160: [[Int]] = [
        [36, 40, 44, 48, 52, 56, 60, 64],
        [100, 104, 108, 112, 116, 120, 124, 128],
    ]

    private static func blockCenter(_ blocks: [[Int]], _ ch: Int) -> Double? {
        guard let b = blocks.first(where: { $0.contains(ch) }) else { return nil }
        let lo = centerFrequency(channel: b.first!, band: .ghz5)
        let hi = centerFrequency(channel: b.last!, band: .ghz5)
        return (lo + hi) / 2
    }

    /// REAL center frequency of the carrier, accounting for channel width.
    static func carrierCenter(channel ch: Int, band: Band, width w: CWChannelWidth) -> Double {
        let primary = centerFrequency(channel: ch, band: band)
        let mhz = widthMHz(w)
        guard mhz > 20 else { return primary }

        switch band {
        case .ghz24:
            // In 2.4 GHz the secondary channel direction (HT40+/-) only lives in
            // the Information Element, which CoreWLAN does not expose. Use primary.
            return primary

        case .ghz5:
            let blocks: [[Int]]
            switch mhz {
            case 40:  blocks = blocks5GHz40
            case 80:  blocks = blocks5GHz80
            default:  blocks = blocks5GHz160
            }
            return blockCenter(blocks, ch) ?? primary

        case .ghz6:
            // 6 GHz 40 / 80 / 160 MHz blocks are regular and aligned from
            // channel 1. 320 MHz is not: 320-1 and 320-2 overlap, so this
            // formula must not be used for it. `resolve` places 320 MHz.
            let n = Int(mhz) / 20                      // 2, 4 or 8 channels
            let span = n * 4                           // 6 GHz channels step by 4
            let base = span * ((ch - 1) / span) + 1     // first channel of the block
            let lo = centerFrequency(channel: base, band: .ghz6)
            let hi = centerFrequency(channel: base + span - 4, band: .ghz6)
            return (lo + hi) / 2
        }
    }

    // MARK: 320 MHz (Wi-Fi 7, 6 GHz)

    // IEEE 802.11be 6 GHz 320 MHz channelisation. Each block is sixteen
    // 20 MHz primaries. The two plans overlap, so a primary such as 37 belongs
    // to both center 31 (320-1) and center 63 (320-2).
    //
    //   320-1: centers 31, 95, 159   primaries 1–61, 65–125, 129–189
    //   320-2: centers 63, 127, 191  primaries 33–93, 97–157, 161–221
    private struct Block320 {
        let plan: String
        let centerChannel: Int
        let low: Int
        let high: Int

        func contains(primary: Int) -> Bool {
            primary >= low && primary <= high && (primary - low) % 4 == 0
        }
    }

    private static let blocks320: [Block320] = [
        .init(plan: "320-1", centerChannel: 31,  low: 1,   high: 61),
        .init(plan: "320-1", centerChannel: 95,  low: 65,  high: 125),
        .init(plan: "320-1", centerChannel: 159, low: 129, high: 189),
        .init(plan: "320-2", centerChannel: 63,  low: 33,  high: 93),
        .init(plan: "320-2", centerChannel: 127, low: 97,  high: 157),
        .init(plan: "320-2", centerChannel: 191, low: 161, high: 221),
    ]

    /// Element ID 255, Element ID Extension 106 (IEEE 802.11be EHT Operation).
    private static let extensionElementID: UInt8 = 255
    private static let ehtOperationExtensionID: UInt8 = 106

    /// EHT Operation element, if the buffer contains one.
    ///
    /// `CWNetwork.informationElementData` is the beacon/probe information-element
    /// chain (tag, length, value), with no 802.11 header and no beacon fixed
    /// fields — that is what a scan on macOS 26.5.1 returns. A chain that does
    /// not parse is tried again at offset 12, in case a future OS prepends the
    /// 12-byte beacon fixed fields.
    static func ehtOperation(in data: Data) -> EHTOperationInfo? {
        if data.isEmpty { return nil }
        let bytes = [UInt8](data)
        switch walkIEs(bytes, start: 0) {
        case .valid(let op):
            return op
        case .invalid:
            guard bytes.count > 12 else { return nil }
            if case .valid(let op) = walkIEs(bytes, start: 12) { return op }
            return nil
        }
    }

    private enum IEWalk {
        case valid(EHTOperationInfo?)
        case invalid
    }

    private static func walkIEs(_ bytes: [UInt8], start: Int) -> IEWalk {
        var i = start
        var found: EHTOperationInfo?
        while i < bytes.count {
            guard i + 1 < bytes.count else { return .invalid }
            let id = bytes[i]
            let len = Int(bytes[i + 1])
            let next = i + 2 + len
            guard next <= bytes.count else { return .invalid }
            if id == extensionElementID, len >= 1, bytes[i + 2] == ehtOperationExtensionID {
                let payload = Array(bytes[(i + 3)..<next])
                if let op = parseEHTPayload(payload) { found = op }
            }
            i = next
        }
        return .valid(found)
    }

    /// Payload is the EHT Operation element after the extension id:
    /// parameters (1) + Basic EHT-MCS And NSS Set (4) + optional operation
    /// information. Channel width is the low 3 bits of the control octet
    /// (0=20, 1=40, 2=80, 3=160, 4=320). For 320 MHz, CCFS1 is the 320 MHz
    /// center and CCFS0 is the primary 160 MHz center.
    private static func parseEHTPayload(_ payload: [UInt8]) -> EHTOperationInfo? {
        guard payload.count >= 5 else { return nil }
        let params = payload[0]
        let infoPresent = params & 0x01 != 0
        guard infoPresent else {
            return EHTOperationInfo(widthMHz: nil, ccfs0: nil, ccfs1: nil)
        }
        var needed = 8 // 5 fixed + control + CCFS0 + CCFS1
        if params & 0x02 != 0 { needed += 2 } // Disabled Subchannel Bitmap
        guard payload.count >= needed else { return nil }
        let widthCode = payload[5] & 0x07
        let width: Int?
        switch widthCode {
        case 0: width = 20
        case 1: width = 40
        case 2: width = 80
        case 3: width = 160
        case 4: width = 320
        default: width = nil
        }
        return EHTOperationInfo(widthMHz: width, ccfs0: Int(payload[6]), ccfs1: Int(payload[7]))
    }

    /// Width and real carrier center for one BSS.
    ///
    /// 20/40/80/160 MHz keep using CoreWLAN plus the block tables above.
    /// 320 MHz comes from the EHT Operation element, because CoreWLAN cannot
    /// say it. CCFS1 (then CCFS0) is accepted when it is a standard 320 MHz
    /// center that actually contains the primary. Otherwise a primary that
    /// sits in only one plan selects that plan, and a primary that sits in
    /// both is left ambiguous — both blocks, neither preferred.
    static func resolve(channel: Int, band: Band, width: CWChannelWidth,
                        informationElements: Data?) -> ResolvedCarrier {
        let eht = informationElements.flatMap { ehtOperation(in: $0) }
        if eht?.widthMHz == 320 {
            return resolve320(channel: channel, band: band,
                              ccfs0: eht?.ccfs0, ccfs1: eht?.ccfs1, fromIE: true)
        }

        let fromCoreWLAN = knownWidthMHz(width)
        let fromIE = eht?.widthMHz.flatMap { (20...160).contains($0) ? $0 : nil }
        let mhz = fromCoreWLAN ?? fromIE ?? 20
        let center = carrierCenter(channel: channel, band: band, width: widthMatching(mhz))
        return ResolvedCarrier(
            widthMHz: mhz,
            spans: [SpectrumSpan(centerMHz: center, widthMHz: mhz, candidate: false, plan: nil)],
            block: nil,
            ambiguous: false,
            widthKnown: fromCoreWLAN != nil || fromIE != nil,
            learnedFromIE: fromCoreWLAN == nil && fromIE != nil
        )
    }

    private static func widthMatching(_ mhz: Double) -> CWChannelWidth {
        switch mhz {
        case 40:  return .width40MHz
        case 80:  return .width80MHz
        case 160: return .width160MHz
        default:  return .width20MHz
        }
    }

    private static func resolve320(channel: Int, band: Band,
                                   ccfs0: Int?, ccfs1: Int?, fromIE: Bool) -> ResolvedCarrier {
        func finish(_ spans: [SpectrumSpan], block: String?, ambiguous: Bool) -> ResolvedCarrier {
            ResolvedCarrier(widthMHz: 320, spans: spans, block: block,
                            ambiguous: ambiguous, widthKnown: true, learnedFromIE: fromIE)
        }
        // 320 MHz channelisation is a 6 GHz fact. Do not invent a span elsewhere.
        guard band == .ghz6 else { return finish([], block: nil, ambiguous: true) }

        func named(_ center: Int) -> Block320? {
            guard let block = blocks320.first(where: { $0.centerChannel == center }) else { return nil }
            return block.contains(primary: channel) ? block : nil
        }
        if let block = ccfs1.flatMap(named) ?? ccfs0.flatMap(named) {
            return finish([span(for: block, candidate: false)], block: block.plan, ambiguous: false)
        }

        let containing = blocks320.filter { $0.contains(primary: channel) }
        if containing.count == 1, let only = containing.first {
            return finish([span(for: only, candidate: false)], block: only.plan, ambiguous: false)
        }
        if containing.count >= 2 {
            let spans = containing.map { span(for: $0, candidate: true) }
                .sorted { $0.centerMHz < $1.centerMHz }
            return finish(spans, block: nil, ambiguous: true)
        }
        return finish([], block: nil, ambiguous: true)
    }

    private static func span(for block: Block320, candidate: Bool) -> SpectrumSpan {
        SpectrumSpan(
            centerMHz: centerFrequency(channel: block.centerChannel, band: .ghz6),
            widthMHz: 320,
            candidate: candidate,
            plan: block.plan
        )
    }
}

// MARK: - Resolved carrier

struct EHTOperationInfo: Equatable, Sendable {
    var widthMHz: Int?
    var ccfs0: Int?
    var ccfs1: Int?
}

struct SpectrumSpan: Hashable, Sendable {
    var centerMHz: Double
    var widthMHz: Double
    var candidate: Bool
    /// "320-1" or "320-2" when this span is one of those blocks.
    var plan: String?
}

struct ResolvedCarrier: Hashable, Sendable {
    var widthMHz: Double
    var spans: [SpectrumSpan]
    /// "320-1" or "320-2" when the block is known. Nil when it is not 320 MHz,
    /// or when the two plans cannot be told apart.
    var block: String?
    var ambiguous: Bool
    var widthKnown: Bool
    var learnedFromIE: Bool

    static let unknown = ResolvedCarrier(
        widthMHz: 20, spans: [], block: nil, ambiguous: false,
        widthKnown: false, learnedFromIE: false
    )

    /// Anchor for the chart label: the one center, or the midpoint of the
    /// candidate blocks (which sits in their overlap).
    var labelMHz: Double? {
        guard !spans.isEmpty else { return nil }
        let sum = spans.reduce(0.0) { $0 + $1.centerMHz }
        return sum / Double(spans.count)
    }

    var showsCandidates: Bool { ambiguous && spans.count >= 2 }

    var widthText: String {
        widthKnown ? "\(Int(widthMHz)) MHz" : "-"
    }

    var centerText: String {
        if spans.count >= 2 {
            let parts = spans.map { span -> String in
                let mhz = "\(Int(span.centerMHz))"
                if let plan = span.plan { return "\(mhz) (\(plan))" }
                return mhz
            }
            return "ambiguous · " + parts.joined(separator: " or ") + " MHz"
        }
        if let span = spans.first {
            let base = "\(Int(span.centerMHz)) MHz"
            if let block { return "\(base) (\(block))" }
            return base
        }
        return widthMHz == 320 ? "unknown" : "-"
    }

    var rangeText: String {
        func piece(_ span: SpectrumSpan) -> String {
            let lo = Int(span.centerMHz - span.widthMHz / 2)
            let hi = Int(span.centerMHz + span.widthMHz / 2)
            let range = "\(lo)–\(hi)"
            if let plan = span.plan { return "\(range) (\(plan))" }
            return range
        }
        if spans.count == 1, let span = spans.first {
            let lo = Int(span.centerMHz - span.widthMHz / 2)
            let hi = Int(span.centerMHz + span.widthMHz / 2)
            return "\(lo) – \(hi) MHz"
        }
        if spans.count >= 2 {
            return spans.map(piece).joined(separator: " or ") + " MHz"
        }
        return widthMHz == 320 ? "unknown" : "-"
    }

    /// Value for the details row that only appears on a 320 MHz network.
    var blockText: String {
        if let block { return block }
        if showsCandidates { return "ambiguous (320-1 or 320-2)" }
        if widthMHz == 320 { return "unknown" }
        return "-"
    }
}

// MARK: - Network

struct WifiNetwork: Identifiable, Hashable {
    let ssid: String
    let bssid: String
    let rssi: Int
    let noise: Int
    let channel: Int
    let band: Band
    let width: CWChannelWidth
    let security: String
    let phyMode: String
    let isConnected: Bool
    /// Beacon/probe information elements from `CWNetwork.informationElementData`.
    /// Nil when CoreWLAN does not provide them (no location permission, or an
    /// older scan path). The EHT Operation element lives in here.
    let informationElements: Data? = nil

    var id: String { bssid.isEmpty ? "\(ssid)-\(channel)" : bssid }

    var isHidden: Bool { ssid.isEmpty }
    var displaySSID: String { isHidden ? "(hidden)" : ssid }

    var carrier: ResolvedCarrier {
        ChannelPlan.resolve(channel: channel, band: band, width: width,
                            informationElements: informationElements)
    }

    var widthMHz: Double { carrier.widthMHz }
    /// Chart-label anchor. For an ambiguous 320 MHz network this is the
    /// midpoint of the two candidate centers, not a claim that the carrier
    /// is there.
    var centerMHz: Double {
        carrier.labelMHz ?? ChannelPlan.centerFrequency(channel: channel, band: band)
    }
    var chartLabel: String {
        carrier.showsCandidates ? "\(displaySSID) · 320?" : displaySSID
    }

    /// SNR in dB. CoreWLAN only fills `noise` for the connected interface, so
    /// for neighbors we fall back to the locally measured noise floor.
    func snr(noiseFloor: Int) -> Int {
        let floor = noise != 0 ? noise : noiseFloor
        return rssi - floor
    }

    /// Quality 0...1 derived from RSSI, used to tint the UI.
    var quality: Double {
        let clamped = Double(min(max(rssi, -100), -30))
        return (clamped + 100) / 70
    }

    var qualityLabel: String {
        switch rssi {
        case (-55)...:      return "Excellent"
        case (-67)..<(-55): return "Good"
        case (-75)..<(-67): return "Fair"
        default:            return "Poor"
        }
    }

    /// Points of one spectral curve. Parabola peaking at RSSI with its base
    /// spanning the occupied width. An ambiguous 320 MHz network has two of
    /// these — use `curves`, which returns every span.
    func curve(floor: Double = -100, samples: Int = 33) -> [(mhz: Double, rssi: Double)] {
        guard let span = carrier.spans.first(where: { !$0.candidate }) ?? carrier.spans.first else {
            return []
        }
        return Self.parabola(center: span.centerMHz, width: span.widthMHz,
                             rssi: rssi, floor: floor, samples: samples)
    }

    /// One parabola per occupied span. Candidate spans are the two possible
    /// 320 MHz blocks when the beacon did not say which plan is in use.
    func curves(floor: Double = -100, samples: Int = 33) -> [(span: SpectrumSpan, points: [(mhz: Double, rssi: Double)])] {
        carrier.spans.map { span in
            (span, Self.parabola(center: span.centerMHz, width: span.widthMHz,
                                 rssi: rssi, floor: floor, samples: samples))
        }
    }

    private static func parabola(center: Double, width: Double, rssi: Int,
                                 floor: Double, samples: Int) -> [(mhz: Double, rssi: Double)] {
        let half = width / 2
        let peak = Double(rssi)
        guard half > 0, peak > floor else { return [] }
        return (0...samples).map { i in
            let t = Double(i) / Double(samples)          // 0...1
            let x = center - half + t * width
            let d = (x - center) / half                  // -1...1
            let y = floor + (peak - floor) * (1 - d * d)
            return (x, y)
        }
    }
}

// MARK: - Formatting helpers

enum Describe {
    static func security(_ n: CWNetwork) -> String {
        let map: [(CWSecurity, String)] = [
            (.none, "Open"), (.WEP, "WEP"),
            (.wpaPersonal, "WPA"), (.wpaPersonalMixed, "WPA/WPA2"),
            (.wpa2Personal, "WPA2"), (.wpa3Personal, "WPA3"),
            (.wpa3Transition, "WPA2/WPA3"), (.wpa3Enterprise, "WPA3 Enterprise"),
            (.wpaEnterprise, "WPA Enterprise"), (.wpaEnterpriseMixed, "WPA/WPA2 Enterprise"),
            (.wpa2Enterprise, "WPA2 Enterprise"), (.enterprise, "Enterprise"),
            (.personal, "Personal"), (.dynamicWEP, "Dynamic WEP"),
        ]
        for (s, label) in map where n.supportsSecurity(s) { return label }
        return "Unknown"
    }

    /// Security of the connected interface (CWInterface.security()), which uses
    /// the same enum as scanned networks but is queried directly.
    static func interfaceSecurity(_ s: CWSecurity) -> String {
        switch s {
        case .none:               return "Open"
        case .WEP:                return "WEP"
        case .wpaPersonal:        return "WPA Personal"
        case .wpaPersonalMixed:   return "WPA/WPA2 Personal"
        case .wpa2Personal:       return "WPA2 Personal"
        case .wpa3Personal:       return "WPA3 Personal"
        case .wpa3Transition:     return "WPA2/WPA3 Transition"
        case .wpa3Enterprise:     return "WPA3 Enterprise"
        case .wpaEnterprise:      return "WPA Enterprise"
        case .wpaEnterpriseMixed: return "WPA/WPA2 Enterprise"
        case .wpa2Enterprise:     return "WPA2 Enterprise"
        case .personal:           return "Personal"
        case .enterprise:         return "Enterprise"
        case .dynamicWEP:         return "Dynamic WEP"
        case .OWE:                return "OWE"
        case .oweTransition:      return "OWE Transition"
        case .unknown:            return "Unknown"
        @unknown default:         return "Unknown"
        }
    }

    static func phy(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a:  return "Wi-Fi 1 (a)"
        case .mode11b:  return "Wi-Fi 2 (b)"
        case .mode11g:  return "Wi-Fi 3 (g)"
        case .mode11n:  return "Wi-Fi 4 (n)"
        case .mode11ac: return "Wi-Fi 5 (ac)"
        case .mode11ax: return "Wi-Fi 6 (ax)"
        default:
            // kCWPHYMode11be = 7, added in the Xcode 26.4 SDK. Match the raw
            // value so this still builds against older headers, which stop at ax.
            if mode.rawValue == 7 { return "Wi-Fi 7 (be)" }
            return "-"
        }
    }

    static func width(_ w: CWChannelWidth) -> String {
        w == .widthUnknown ? "-" : "\(Int(ChannelPlan.widthMHz(w))) MHz"
    }
}
