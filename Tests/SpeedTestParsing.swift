import Foundation

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/fixtures-networkquality.json"
let data = try! Data(contentsOf: URL(fileURLWithPath: path))
let r = try! SpeedResult.parse(data)

var failures = 0
func check(_ name: String, _ got: String, _ expected: String) {
    let ok = got == expected
    if !ok { failures += 1 }
    print(String(format: "  %-22@ %-26@ %@", name as NSString, got as NSString,
                 (ok ? "OK" : "FAILED (expected \(expected))") as NSString))
}

print("Decoding real output of networkquality -c:")
check("download",       String(format: "%.1f Mbps", r.downloadMbps), "8.7 Mbps")
check("upload",         String(format: "%.1f Mbps", r.uploadMbps),   "90.6 Mbps")
check("RTT base",       String(format: "%.0f ms", r.baseRttMs),      "33 ms")
check("responsiveness", String(format: "%.0f RPM", r.responsiveness), "30 RPM")
check("rating",         r.responsivenessLabel,                        "Low")
check("latency",        r.latencyLabel,                               "Good")
check("interface",      r.interfaceName,                              "en0")
check("endpoint",       r.testEndpoint,             "brsao4-edge-bx-002.aaplimg.com")
check("duration",       String(format: "%.0f s", r.durationSec),      "37 s")

// Robustness: incomplete JSON must not crash the app
print("\nTolerance to partial output:")
let partial = #"{"dl_throughput": 1000000, "ul_throughput": 2000000}"#.data(using: .utf8)!
if let p = try? SpeedResult.parse(partial) {
    print("  missing fields default          OK (\(String(format: "%.0f", p.downloadMbps)) Mbps, rtt \(p.baseRttMs))")
} else { failures += 1; print("  partial parse                   FAILED") }

let empty = #"{}"#.data(using: .utf8)!
if (try? SpeedResult.parse(empty)) == nil {
    print("  JSON without throughput rejected OK")
} else { failures += 1; print("  empty JSON should have failed   FAILED") }

print("")
print(failures == 0 ? "ALL CASES PASSED" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
