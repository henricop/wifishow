import Foundation
import CoreWLAN

// Validates the mapping from primary channel to real carrier center.
struct Case_ { let ssid: String; let ch: Int; let band: Band; let w: CWChannelWidth; let expectedCenterChannel: Int }

// Cases derived from real scans, with SSIDs anonymized.
// What matters is the triple (primary channel, width, expected center).
let cases: [Case_] = [
    // 5 GHz: canonical blocks, including the edges of each grouping
    .init(ssid: "UNII1-160MHz", ch: 44,  band: .ghz5,  w: .width160MHz, expectedCenterChannel: 50),
    .init(ssid: "UNII1-80MHz",  ch: 40,  band: .ghz5,  w: .width80MHz,  expectedCenterChannel: 42),
    .init(ssid: "UNII1-edge ",  ch: 36,  band: .ghz5,  w: .width80MHz,  expectedCenterChannel: 42),
    // UNII-3 breaks the step-of-4 pattern: where the naive formula fails
    .init(ssid: "UNII3-80MHz",  ch: 149, band: .ghz5,  w: .width80MHz,  expectedCenterChannel: 155),
    .init(ssid: "UNII3-top ",   ch: 161, band: .ghz5,  w: .width80MHz,  expectedCenterChannel: 155),
    .init(ssid: "UNII2-160MHz", ch: 100, band: .ghz5,  w: .width160MHz, expectedCenterChannel: 114),
    // 2.4 GHz: narrow channel, center == primary
    .init(ssid: "24GHz-20MHz",  ch: 11,  band: .ghz24, w: .width20MHz,  expectedCenterChannel: 11),
    .init(ssid: "24GHz-ch1",    ch: 1,   band: .ghz24, w: .width20MHz,  expectedCenterChannel: 1),
    // 6 GHz: regular blocks resolved by formula
    .init(ssid: "6GHz-40MHz",   ch: 9,   band: .ghz6,  w: .width40MHz,  expectedCenterChannel: 11),
    .init(ssid: "6GHz-80MHz",   ch: 17,  band: .ghz6,  w: .width80MHz,  expectedCenterChannel: 23),
    .init(ssid: "6GHz-160MHz",  ch: 1,   band: .ghz6,  w: .width160MHz, expectedCenterChannel: 15),
    .init(ssid: "6GHz-high",    ch: 213, band: .ghz6,  w: .width80MHz,  expectedCenterChannel: 215),
]

var failures = 0
print("network           ch   width    computed       expected   ok")
print(String(repeating: "-", count: 66))
for c in cases {
    let center = ChannelPlan.carrierCenter(channel: c.ch, band: c.band, width: c.w)
    let expected = ChannelPlan.centerFrequency(channel: c.expectedCenterChannel, band: c.band)
    let ok = abs(center - expected) < 0.01
    if !ok { failures += 1 }
    print(String(format: "%-17@ %-4d %-8@ %-14.0f %-10.0f %@",
                 c.ssid as NSString, c.ch, Describe.width(c.w) as NSString,
                 center, expected, (ok ? "OK" : "FAILED") as NSString))
}

print("")
print("Spectral occupancy (edges of the drawn curve):")
for c in cases.prefix(5) {
    let n = WifiNetwork(ssid: c.ssid, bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, noise: 0,
                        channel: c.ch, band: c.band, width: c.w,
                        security: "WPA2", phyMode: "-", isConnected: false)
    let curve = n.curve()
    print(String(format: "  %-13@ occupies %.0f - %.0f MHz (%.0f MHz wide)",
                 c.ssid as NSString, curve.first!.mhz, curve.last!.mhz, n.widthMHz))
}

// MARK: - 320 MHz (Wi-Fi 7)

// EHT Operation element, IEEE 802.11be.
// Element ID 255, extension 106. For 320 MHz the control field's low 3 bits
// are 4, CCFS0 is the primary 160 MHz center, and CCFS1 is the 320 MHz center.
func ehtIE(widthCode: UInt8, ccfs0: UInt8, ccfs1: UInt8,
           params: UInt8 = 0x01, bitmap: [UInt8] = []) -> [UInt8] {
    var value: [UInt8] = [106, params, 0x11, 0x00, 0x00, 0x00, widthCode, ccfs0, ccfs1]
    value.append(contentsOf: bitmap)
    return [255, UInt8(value.count)] + value
}

func expect(_ ok: Bool, _ name: String) {
    if ok {
        print("OK      \(name)")
    } else {
        failures += 1
        print("FAILED  \(name)")
    }
}

func resolved(ch: Int, w: CWChannelWidth, ie: [UInt8]? = nil, band: Band = .ghz6) -> ResolvedCarrier {
    ChannelPlan.resolve(channel: ch, band: band, width: w,
                        informationElements: ie.map { Data($0) })
}

print("")
print("320 MHz — EHT Operation element, 320-1 / 320-2, ambiguity")
print(String(repeating: "-", count: 66))

// Published capture shape: primary 37, CCFS0 47, CCFS1 31 → 320-1 at 6105 MHz.
// CoreWLAN is handed 20 MHz on purpose: the IE has to win, or this still draws as 20.
let plan1 = resolved(ch: 37, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 47, ccfs1: 31))
expect(plan1.widthMHz == 320, "320-1 width is 320, not the CoreWLAN 20 MHz fallback")
expect(plan1.widthText == "320 MHz", "320-1 width text is 320 MHz")
expect(plan1.block == "320-1", "primary 37 + CCFS1 31 is 320-1")
expect(!plan1.ambiguous && plan1.spans.count == 1, "320-1 is a single span")
expect(plan1.spans.first.map { Int($0.centerMHz) } == 6105, "320-1 center is 6105 MHz (channel 31)")
expect(plan1.centerText == "6105 MHz (320-1)", "320-1 center text names the plan")
expect(plan1.rangeText == "5945 – 6265 MHz", "320-1 occupies 5945–6265 MHz")

let plan1Net = WifiNetwork(ssid: "6GHz-320-1", bssid: "aa:bb:cc:dd:ee:01", rssi: -40, noise: 0,
                           channel: 37, band: .ghz6, width: .width20MHz,
                           security: "WPA3", phyMode: "-", isConnected: false,
                           informationElements: Data(ehtIE(widthCode: 4, ccfs0: 47, ccfs1: 31)))
let plan1Curve = plan1Net.curve()
expect(plan1Curve.count > 1, "320-1 curve is drawn")
expect(abs(plan1Curve.last!.mhz - plan1Curve.first!.mhz - 320) < 0.01, "320-1 curve is 320 MHz wide")
expect(abs(plan1Net.widthMHz - 320) < 0.01, "WifiNetwork.widthMHz is 320")

// Same primary, the other plan. The channel-1 alignment formula would pick
// 320-1 (center 31). CCFS1 = 63 must place it on 320-2 instead.
let plan2 = resolved(ch: 37, w: .width160MHz, ie: ehtIE(widthCode: 4, ccfs0: 47, ccfs1: 63))
expect(plan2.widthMHz == 320, "320-2 wins over a CoreWLAN 160 MHz report")
expect(plan2.block == "320-2", "primary 37 + CCFS1 63 is 320-2")
expect(plan2.spans.first.map { Int($0.centerMHz) } == 6265, "320-2 center is 6265 MHz (channel 63)")
expect(plan2.centerText == "6265 MHz (320-2)", "320-2 center text names the plan")

// Overlap further up the band, where alignment-from-channel-1 is 320-1
// (center 95) and the beacon says 320-2 (center 63).
let overlap = resolved(ch: 69, w: .width80MHz, ie: ehtIE(widthCode: 4, ccfs0: 79, ccfs1: 63))
expect(overlap.block == "320-2", "primary 69 is not forced onto the channel-1 320-1 block")
expect(overlap.spans.first.map { Int($0.centerMHz) } == 6265, "primary 69 + CCFS1 63 centers at 6265")

// High blocks, one of each plan.
let high1 = resolved(ch: 149, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 143, ccfs1: 159))
expect(high1.block == "320-1" && high1.spans.first.map { Int($0.centerMHz) } == 6745,
       "320-1 high block center channel 159 is 6745 MHz")
let high2 = resolved(ch: 209, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 207, ccfs1: 191))
expect(high2.block == "320-2" && high2.spans.first.map { Int($0.centerMHz) } == 6905,
       "320-2 high block center channel 191 is 6905 MHz")

// CCFS1 wins when both fields name a block that contains the primary.
let preferCCFS1 = resolved(ch: 37, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 31, ccfs1: 63))
expect(preferCCFS1.block == "320-2", "CCFS1 is the 320 MHz center when both fields are plausible")

// A center that does not contain the primary is ignored. CCFS0 may still name it.
let ccfs0Fallback = resolved(ch: 37, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 31, ccfs1: 0))
expect(ccfs0Fallback.block == "320-1", "CCFS0 is used when it, not CCFS1, names the block")

// No usable center, but the primary sits in only one plan.
let only1 = resolved(ch: 1, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 0, ccfs1: 0))
expect(only1.block == "320-1" && !only1.ambiguous, "channel 1 can only be 320-1")
let only2 = resolved(ch: 193, w: .width160MHz, ie: ehtIE(widthCode: 4, ccfs0: 0, ccfs1: 0))
expect(only2.block == "320-2" && only2.spans.first.map { Int($0.centerMHz) } == 6905,
       "channel 193 can only be 320-2")

// No usable center, primary in both plans: say so, and do not draw 320-1 by default.
let ambiguous = resolved(ch: 37, w: .width160MHz, ie: ehtIE(widthCode: 4, ccfs0: 0, ccfs1: 0))
expect(ambiguous.ambiguous && ambiguous.showsCandidates, "overlap without a center is ambiguous")
expect(ambiguous.widthText == "320 MHz", "ambiguous network still displays 320 MHz")
expect(ambiguous.spans.count == 2 && ambiguous.spans.allSatisfy(\.candidate), "both blocks are candidates")
expect(ambiguous.spans.map { Int($0.centerMHz) } == [6105, 6265], "candidates are 6105 and 6265 MHz")
expect(ambiguous.centerText == "ambiguous · 6105 (320-1) or 6265 (320-2) MHz",
       "center text is marked ambiguous and names both plans")
expect(ambiguous.blockText == "ambiguous (320-1 or 320-2)", "block text says ambiguous")

let ambiguousNet = WifiNetwork(ssid: "maybe", bssid: "aa:bb:cc:dd:ee:02", rssi: -48, noise: 0,
                               channel: 37, band: .ghz6, width: .width20MHz,
                               security: "WPA3", phyMode: "-", isConnected: false,
                               informationElements: Data(ehtIE(widthCode: 4, ccfs0: 0, ccfs1: 0)))
expect(ambiguousNet.chartLabel == "maybe · 320?", "chart label carries 320?")
expect(ambiguousNet.curves().count == 2, "chart draws both candidate curves")
expect(ambiguousNet.curves().allSatisfy { $0.span.candidate }, "both drawn curves are candidates")

// Not a standard 320 MHz primary (above channel 221). Width is still 320;
// there is no span to draw in the wrong place.
let nowhere = resolved(ch: 225, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 0, ccfs1: 0))
expect(nowhere.widthMHz == 320 && nowhere.spans.isEmpty && nowhere.centerText == "unknown",
       "channel 225 is 320 MHz with an unknown center, not a 20 MHz drawing")

// Puncturing bitmap (2 extra octets) and a high bit in the control field must
// not shift CCFS0/CCFS1. Control 0x84 is width 4 plus a reserved bit.
let punctured = ehtIE(widthCode: 0x84, ccfs0: 47, ccfs1: 31, params: 0x03, bitmap: [0x01, 0x00])
let withBitmap = resolved(ch: 37, w: .width20MHz, ie: punctured)
expect(withBitmap.block == "320-1" && withBitmap.spans.first.map { Int($0.centerMHz) } == 6105,
       "disabled-subchannel bitmap does not shift the 320 MHz center")

// The element sits behind other IEs, which is how CoreWLAN returns the chain.
let ssid: [UInt8] = [0, 4, 0x77, 0x69, 0x66, 0x69] // "wifi"
let wrapped = resolved(ch: 37, w: .width20MHz, ie: ssid + ehtIE(widthCode: 4, ccfs0: 47, ccfs1: 31))
expect(wrapped.block == "320-1", "EHT Operation is found after a preceding SSID element")

// 12-byte beacon fixed fields in front of a chain that is not valid TLV at offset 0.
var prefixed = [UInt8](repeating: 0, count: 12)
prefixed[0] = 1
prefixed[1] = 255 // length overruns, so the walk at offset 0 fails
prefixed.append(contentsOf: ehtIE(widthCode: 4, ccfs0: 47, ccfs1: 31))
let prefixedCarrier = resolved(ch: 37, w: .width20MHz, ie: prefixed)
expect(prefixedCarrier.block == "320-1", "IE chain is retried after a 12-byte beacon header")

// A truncated EHT element is ignored. Width stays whatever CoreWLAN said.
let truncated: [UInt8] = [255, 6, 106, 0x01, 0x11, 0x00, 0x00, 0x00]
let ignored = resolved(ch: 17, w: .width80MHz, ie: truncated)
let eighty = ChannelPlan.centerFrequency(channel: 23, band: .ghz6)
expect(ignored.widthMHz == 80 && ignored.spans.first.map { abs($0.centerMHz - eighty) < 0.01 } == true,
       "a truncated EHT element does not override an 80 MHz CoreWLAN width")

// No IE at all: 160 MHz stays on the 160 MHz formula. Channel 37 is center 47,
// not a guess at a 320 MHz block.
let still160 = resolved(ch: 37, w: .width160MHz, ie: nil)
let oneSixty = ChannelPlan.centerFrequency(channel: 47, band: .ghz6)
expect(still160.widthMHz == 160 && still160.learnedFromIE == false, "without an IE, 160 MHz stays 160")
expect(still160.spans.first.map { abs($0.centerMHz - oneSixty) < 0.01 } == true,
       "without an IE, channel 37 at 160 MHz stays centered on channel 47")

// Parser rejects a buffer that is not an IE chain.
expect(ChannelPlan.ehtOperation(in: Data([0x00, 0x05])) == nil, "short garbage is not an EHT Operation element")
let parsed = ChannelPlan.ehtOperation(in: Data(ehtIE(widthCode: 4, ccfs0: 47, ccfs1: 31)))
expect(parsed?.widthMHz == 320 && parsed?.ccfs0 == 47 && parsed?.ccfs1 == 31,
       "parser returns width 320, CCFS0 47, CCFS1 31")

// 320 MHz is a 6 GHz channelisation. Don't draw it on another band.
let not6 = resolved(ch: 36, w: .width20MHz, ie: ehtIE(widthCode: 4, ccfs0: 50, ccfs1: 31), band: .ghz5)
expect(not6.widthMHz == 320 && not6.spans.isEmpty && not6.centerText == "unknown",
       "320 MHz on 5 GHz is reported as unknown placement, not a 20 MHz curve")

print("")
print(failures == 0 ? "ALL CASES PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
