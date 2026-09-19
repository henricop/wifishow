import Foundation
import CoreWLAN
import Darwin

// MARK: - Retrato completo da interface conectada
//
// O scan devolve pouca coisa das redes vizinhas, mas da interface conectada o
// CoreWLAN expoe bem mais: taxa de transmissao, potencia, codigo do pais,
// modo PHY, MAC do adaptador. Esta tela reune tudo em um lugar so.

struct InterfaceDetails {
    var interfaceName  = "-"
    var hardwareAddress = "-"
    var ssid           = "-"
    var bssid          = "-"
    var rssi           = 0
    var noise          = 0
    var transmitRate   = 0.0
    var transmitPower  = 0
    var countryCode    = "-"
    var security       = "-"
    var phyMode        = "-"
    var channel        = 0
    var band: Band?    = nil
    var width: CWChannelWidth = .widthUnknown
    var powerOn        = false
    var serviceActive  = false
    var ipv4           = "-"
    var ipv6           = "-"

    var snr: Int { noise != 0 ? rssi - noise : 0 }

    var centerMHz: Double? {
        guard let b = band, channel > 0 else { return nil }
        return ChannelPlan.carrierCenter(channel: channel, band: b, width: width)
    }

    var occupiedRange: String {
        guard let c = centerMHz else { return "-" }
        let half = ChannelPlan.widthMHz(width) / 2
        return "\(Int(c - half)) – \(Int(c + half)) MHz"
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

    /// Enderecos IP locais da interface, via getifaddrs.
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
            } else if v6 == nil, !addr.hasPrefix("fe80") {   // ignora link-local
                v6 = addr
            }
        }
        return (v4, v6)
    }
}

// MARK: - Item explicado
//
// Cada metrica vem com uma explicacao do que significa. O objetivo e que
// alguem sem formacao em redes consiga ler a tela sem procurar fora.

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
            DetailCategory(title: "Identificação", icon: "tag", items: [
                DetailItem(key: "Nome da rede (SSID)", value: d.ssid,
                           explanation: "Service Set Identifier — o nome que o roteador anuncia. Várias redes podem ter o mesmo nome; o que as distingue é o BSSID."),
                DetailItem(key: "BSSID", value: d.bssid,
                           explanation: "Basic Service Set Identifier — o endereço MAC do ponto de acesso ao qual você está conectado. Em redes mesh, muda quando você troca de nó."),
                DetailItem(key: "Interface", value: d.interfaceName,
                           explanation: "Nome do adaptador Wi-Fi no sistema. Em Macs é quase sempre en0 ou en1."),
                DetailItem(key: "MAC do adaptador", value: d.hardwareAddress,
                           explanation: "Endereço físico da placa Wi-Fi deste Mac. O macOS pode randomizar o endereço apresentado a cada rede, por privacidade."),
                DetailItem(key: "Endereço IPv4", value: d.ipv4,
                           explanation: "Endereço que identifica este Mac na rede local. Normalmente atribuído por DHCP pelo roteador."),
                DetailItem(key: "Endereço IPv6", value: d.ipv6,
                           explanation: "Endereço IPv6 global, quando o provedor oferece. Endereços link-local (fe80::) são omitidos."),
            ]),

            DetailCategory(title: "Sinal", icon: "antenna.radiowaves.left.and.right", items: [
                DetailItem(key: "RSSI", value: "\(d.rssi) dBm",
                           explanation: "Received Signal Strength Indicator — a força do sinal que chega. É negativo: quanto mais perto de zero, melhor. Acima de -55 é excelente; abaixo de -75 começa a doer."),
                DetailItem(key: "Ruído", value: d.noise != 0 ? "\(d.noise) dBm" : "-",
                           explanation: "Energia de fundo na mesma faixa, vinda de outras redes, micro-ondas, Bluetooth. Quanto mais negativo, mais limpo o ambiente."),
                DetailItem(key: "SNR", value: d.snr != 0 ? "\(d.snr) dB" : "-",
                           explanation: "Signal-to-Noise Ratio — a distância entre sinal e ruído, e o número que mais importa. Acima de 40 dB é ótimo; abaixo de 20 dB a velocidade cai muito."),
                DetailItem(key: "Qualidade", value: qualityLabel(d.rssi),
                           explanation: "Leitura direta do RSSI em linguagem comum."),
                DetailItem(key: "Taxa de transmissão", value: d.transmitRate > 0 ? "\(Int(d.transmitRate)) Mbps" : "-",
                           explanation: "Velocidade negociada no rádio agora — não é a velocidade da sua internet. É o teto do enlace entre este Mac e o roteador."),
                DetailItem(key: "Potência de transmissão", value: d.transmitPower > 0 ? "\(d.transmitPower)" : "-",
                           explanation: "Valor bruto de potência reportado pelo driver. A Apple documenta como mW, mas em Macs modernos o número costuma não corresponder a miliwatts reais — o limite legal é de cerca de 100 mW. Sirva-se dele para comparar variações, não como medida absoluta."),
            ]),

            DetailCategory(title: "Canal e frequência", icon: "waveform", items: [
                DetailItem(key: "Canal", value: d.channel > 0 ? "\(d.channel)" : "-",
                           explanation: "Canal primário anunciado pelo roteador. Em canais largos, a portadora ocupa um bloco maior, centrado em outro ponto."),
                DetailItem(key: "Banda", value: d.band?.label ?? "-",
                           explanation: "2.4 GHz alcança mais longe e atravessa paredes, mas é lotada. 5 GHz é mais rápida e limpa, com menos alcance. 6 GHz é a mais limpa e a mais curta."),
                DetailItem(key: "Largura do canal", value: Describe.width(d.width),
                           explanation: "Quanto espectro a rede ocupa. Mais largura dá mais velocidade, mas aumenta a chance de colidir com vizinhos."),
                DetailItem(key: "Frequência central", value: d.centerMHz.map { "\(Int($0)) MHz" } ?? "-",
                           explanation: "Centro real da portadora, já considerando a largura — não é a frequência do canal primário quando o canal é largo."),
                DetailItem(key: "Faixa ocupada", value: d.occupiedRange,
                           explanation: "Intervalo de frequências que esta rede realmente ocupa. Redes cujas faixas se cruzam interferem entre si."),
            ]),

            DetailCategory(title: "Configuração", icon: "gearshape", items: [
                DetailItem(key: "Segurança", value: d.security,
                           explanation: "Protocolo de criptografia. WPA3 é o atual; WPA2 ainda é seguro; WEP e redes abertas não protegem nada."),
                DetailItem(key: "Modo PHY", value: d.phyMode,
                           explanation: "Geração do padrão 802.11 em uso. Wi-Fi 6 (ax) e superiores lidam muito melhor com muitos dispositivos ao mesmo tempo."),
                DetailItem(key: "Código do país", value: d.countryCode,
                           explanation: "País segundo a ISO 3166-1, detectado pelo roteador. Define quais canais e potências são permitidos por lei."),
                DetailItem(key: "Rádio ligado", value: d.powerOn ? "Sim" : "Não",
                           explanation: "Se o rádio Wi-Fi deste Mac está ativo."),
                DetailItem(key: "Serviço ativo", value: d.serviceActive ? "Sim" : "Não",
                           explanation: "Se a interface Wi-Fi está habilitada nas configurações de rede do sistema."),
            ]),
        ]
    }

    private static func qualityLabel(_ rssi: Int) -> String {
        switch rssi {
        case 0:             return "-"
        case (-55)...:      return "Excelente"
        case (-67)..<(-55): return "Bom"
        case (-75)..<(-67): return "Fraco"
        default:            return "Ruim"
        }
    }
}
