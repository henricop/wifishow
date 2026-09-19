import Foundation

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/fixtures-networkquality.json"
let data = try! Data(contentsOf: URL(fileURLWithPath: path))
let r = try! SpeedResult.parse(data)

var falhas = 0
func check(_ nome: String, _ got: String, _ esperado: String) {
    let ok = got == esperado
    if !ok { falhas += 1 }
    print(String(format: "  %-22@ %-26@ %@", nome as NSString, got as NSString,
                 (ok ? "OK" : "FALHOU (esperado \(esperado))") as NSString))
}

print("Decodificacao da saida real do networkquality -c:")
check("download",       String(format: "%.1f Mbps", r.downloadMbps), "8.7 Mbps")
check("upload",         String(format: "%.1f Mbps", r.uploadMbps),   "90.6 Mbps")
check("RTT base",       String(format: "%.0f ms", r.baseRttMs),      "33 ms")
check("responsividade", String(format: "%.0f RPM", r.responsiveness), "30 RPM")
check("classificacao",  r.responsivenessLabel,                        "Baixa")
check("latencia",       r.latencyLabel,                               "Boa")
check("interface",      r.interfaceName,                              "en0")
check("endpoint",       r.testEndpoint,             "brsao4-edge-bx-002.aaplimg.com")
check("duracao",        String(format: "%.0f s", r.durationSec),      "37 s")

// Robustez: JSON incompleto nao pode derrubar o app
print("\nTolerancia a saida parcial:")
let parcial = #"{"dl_throughput": 1000000, "ul_throughput": 2000000}"#.data(using: .utf8)!
if let p = try? SpeedResult.parse(parcial) {
    print("  campos ausentes viram default   OK (\(String(format: "%.0f", p.downloadMbps)) Mbps, rtt \(p.baseRttMs))")
} else { falhas += 1; print("  parse parcial                   FALHOU") }

let vazio = #"{}"#.data(using: .utf8)!
if (try? SpeedResult.parse(vazio)) == nil {
    print("  JSON sem throughput e rejeitado OK")
} else { falhas += 1; print("  JSON vazio deveria falhar       FALHOU") }

print("")
print(falhas == 0 ? "TODOS OS CASOS PASSARAM" : "\(falhas) FALHA(S)")
exit(falhas == 0 ? 0 : 1)
