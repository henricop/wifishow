import Foundation
import CoreWLAN

// Valida o mapeamento canal primario -> centro real da portadora.
struct Caso { let ssid: String; let ch: Int; let band: Band; let w: CWChannelWidth; let esperadoCentroCanal: Int }

// Casos derivados de varreduras reais, com os SSIDs anonimizados.
// O que importa e a tripla (canal primario, largura, centro esperado).
let casos: [Caso] = [
    // 5 GHz: blocos canonicos, incluindo os limites de cada agrupamento
    .init(ssid: "UNII1-160MHz", ch: 44,  band: .ghz5,  w: .width160MHz, esperadoCentroCanal: 50),
    .init(ssid: "UNII1-80MHz",  ch: 40,  band: .ghz5,  w: .width80MHz,  esperadoCentroCanal: 42),
    .init(ssid: "UNII1-borda",  ch: 36,  band: .ghz5,  w: .width80MHz,  esperadoCentroCanal: 42),
    // UNII-3 quebra o passo de 4 em 4: e onde a formula ingenua falha
    .init(ssid: "UNII3-80MHz",  ch: 149, band: .ghz5,  w: .width80MHz,  esperadoCentroCanal: 155),
    .init(ssid: "UNII3-topo",   ch: 161, band: .ghz5,  w: .width80MHz,  esperadoCentroCanal: 155),
    .init(ssid: "UNII2-160MHz", ch: 100, band: .ghz5,  w: .width160MHz, esperadoCentroCanal: 114),
    // 2.4 GHz: canal estreito, centro == primario
    .init(ssid: "24GHz-20MHz",  ch: 11,  band: .ghz24, w: .width20MHz,  esperadoCentroCanal: 11),
    .init(ssid: "24GHz-ch1",    ch: 1,   band: .ghz24, w: .width20MHz,  esperadoCentroCanal: 1),
    // 6 GHz: blocos regulares resolvidos por formula
    .init(ssid: "6GHz-40MHz",   ch: 9,   band: .ghz6,  w: .width40MHz,  esperadoCentroCanal: 11),
    .init(ssid: "6GHz-80MHz",   ch: 17,  band: .ghz6,  w: .width80MHz,  esperadoCentroCanal: 23),
    .init(ssid: "6GHz-160MHz",  ch: 1,   band: .ghz6,  w: .width160MHz, esperadoCentroCanal: 15),
    .init(ssid: "6GHz-alto",    ch: 213, band: .ghz6,  w: .width80MHz,  esperadoCentroCanal: 215),
]

var falhas = 0
print("rede              ch   larg     centro calc   esperado   ok")
print(String(repeating: "-", count: 66))
for c in casos {
    let centro = ChannelPlan.carrierCenter(channel: c.ch, band: c.band, width: c.w)
    let esperado = ChannelPlan.centerFrequency(channel: c.esperadoCentroCanal, band: c.band)
    let ok = abs(centro - esperado) < 0.01
    if !ok { falhas += 1 }
    print(String(format: "%-17@ %-4d %-8@ %-14.0f %-10.0f %@",
                 c.ssid as NSString, c.ch, Describe.width(c.w) as NSString,
                 centro, esperado, (ok ? "OK" : "FALHOU") as NSString))
}

print("")
print("Ocupacao espectral (bordas da curva desenhada):")
for c in casos.prefix(5) {
    let n = WifiNetwork(ssid: c.ssid, bssid: "aa:bb:cc:dd:ee:ff", rssi: -50, noise: 0,
                        channel: c.ch, band: c.band, width: c.w,
                        security: "WPA2", phyMode: "-", isConnected: false)
    let curva = n.curve()
    print(String(format: "  %-13@ ocupa %.0f - %.0f MHz (%.0f MHz de banda)",
                 c.ssid as NSString, curva.first!.mhz, curva.last!.mhz, n.widthMHz))
}

print("")
print(falhas == 0 ? "TODOS OS CASOS PASSARAM" : "\(falhas) FALHA(S)")
exit(falhas == 0 ? 0 : 1)
