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

print("")
print(failures == 0 ? "ALL CASES PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
