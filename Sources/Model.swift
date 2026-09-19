import Foundation
import CoreWLAN

// MARK: - Banda

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

    /// Faixa de frequencia (MHz) usada como dominio do grafico.
    var range: ClosedRange<Double> {
        switch self {
        case .ghz24: return 2400...2500
        case .ghz5:  return 5150...5895
        case .ghz6:  return 5925...7125
        }
    }

    /// Canais que recebem marcacao no eixo X.
    var tickChannels: [Int] {
        switch self {
        case .ghz24: return Array(1...14)
        case .ghz5:  return [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112,
                             116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165]
        case .ghz6:  return stride(from: 1, through: 233, by: 16).map { $0 }
        }
    }
}

// MARK: - Plano de canais

enum ChannelPlan {

    /// Frequencia central (MHz) de um canal primario de 20 MHz.
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

    /// Largura em MHz a partir do enum do CoreWLAN.
    static func widthMHz(_ w: CWChannelWidth) -> Double {
        switch w {
        case .width20MHz:  return 20
        case .width40MHz:  return 40
        case .width80MHz:  return 80
        case .width160MHz: return 160
        default:           return 20
        }
    }

    // Blocos canonicos de 5 GHz: o CoreWLAN entrega o canal PRIMARIO, mas a
    // portadora ocupa o bloco inteiro centrado em outro ponto. Sem isso o
    // grafico desenha a rede no lugar errado.
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

    /// Frequencia central REAL da portadora, considerando a largura do canal.
    static func carrierCenter(channel ch: Int, band: Band, width w: CWChannelWidth) -> Double {
        let primary = centerFrequency(channel: ch, band: band)
        let mhz = widthMHz(w)
        guard mhz > 20 else { return primary }

        switch band {
        case .ghz24:
            // Em 2.4 GHz a direcao do canal secundario (HT40+/-) so vem no
            // Information Element, que o CoreWLAN nao expoe. Centra no primario.
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
            // 6 GHz e regular: blocos alinhados a partir do canal 1.
            let n = Int(mhz) / 20                      // 2, 4 ou 8 canais
            let span = n * 4                           // canais 6 GHz andam de 4 em 4
            let base = span * ((ch - 1) / span) + 1     // primeiro canal do bloco
            let lo = centerFrequency(channel: base, band: .ghz6)
            let hi = centerFrequency(channel: base + span - 4, band: .ghz6)
            return (lo + hi) / 2
        }
    }
}

// MARK: - Rede

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

    var id: String { bssid.isEmpty ? "\(ssid)-\(channel)" : bssid }

    var isHidden: Bool { ssid.isEmpty }
    var displaySSID: String { isHidden ? "(oculta)" : ssid }

    var widthMHz: Double { ChannelPlan.widthMHz(width) }
    var centerMHz: Double { ChannelPlan.carrierCenter(channel: channel, band: band, width: width) }

    /// SNR em dB. O CoreWLAN so preenche `noise` da interface conectada, entao
    /// para as vizinhas usamos o piso de ruido medido localmente.
    func snr(noiseFloor: Int) -> Int {
        let floor = noise != 0 ? noise : noiseFloor
        return rssi - floor
    }

    /// Qualidade 0...1 derivada do RSSI, para colorir a UI.
    var quality: Double {
        let clamped = Double(min(max(rssi, -100), -30))
        return (clamped + 100) / 70
    }

    var qualityLabel: String {
        switch rssi {
        case (-55)...:      return "Excelente"
        case (-67)..<(-55): return "Bom"
        case (-75)..<(-67): return "Fraco"
        default:            return "Ruim"
        }
    }

    /// Pontos da curva espectral desenhada no analyzer.
    /// Parabola com pico no RSSI e base na largura ocupada do canal.
    func curve(floor: Double = -100, samples: Int = 33) -> [(mhz: Double, rssi: Double)] {
        let half = widthMHz / 2
        let peak = Double(rssi)
        let c = centerMHz
        guard peak > floor else { return [] }
        return (0...samples).map { i in
            let t = Double(i) / Double(samples)          // 0...1
            let x = c - half + t * widthMHz
            let d = (x - c) / half                       // -1...1
            let y = floor + (peak - floor) * (1 - d * d)
            return (x, y)
        }
    }
}

// MARK: - Helpers de formatacao

enum Describe {
    static func security(_ n: CWNetwork) -> String {
        let map: [(CWSecurity, String)] = [
            (.none, "Aberta"), (.WEP, "WEP"),
            (.wpaPersonal, "WPA"), (.wpaPersonalMixed, "WPA/WPA2"),
            (.wpa2Personal, "WPA2"), (.wpa3Personal, "WPA3"),
            (.wpa3Transition, "WPA2/WPA3"), (.wpa3Enterprise, "WPA3 Enterprise"),
            (.wpaEnterprise, "WPA Enterprise"), (.wpaEnterpriseMixed, "WPA/WPA2 Enterprise"),
            (.wpa2Enterprise, "WPA2 Enterprise"), (.enterprise, "Enterprise"),
            (.personal, "Personal"), (.dynamicWEP, "WEP dinamico"),
        ]
        for (s, label) in map where n.supportsSecurity(s) { return label }
        return "Desconhecida"
    }

    /// Seguranca da interface conectada (CWInterface.security()), que usa o
    /// mesmo enum das redes escaneadas mas e consultado diretamente.
    static func interfaceSecurity(_ s: CWSecurity) -> String {
        switch s {
        case .none:               return "Aberta"
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
        case .dynamicWEP:         return "WEP dinamico"
        case .OWE:                return "OWE"
        case .oweTransition:      return "OWE Transition"
        case .unknown:            return "Desconhecida"
        @unknown default:         return "Desconhecida"
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
        default:        return "-"
        }
    }

    static func width(_ w: CWChannelWidth) -> String {
        w == .widthUnknown ? "-" : "\(Int(ChannelPlan.widthMHz(w))) MHz"
    }
}
