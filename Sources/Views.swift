import SwiftUI
import Charts
import CoreWLAN

// MARK: - Cor estavel por rede (derivada do BSSID, nao do hashValue)

extension WifiNetwork {
    var hue: Double {
        let seed = bssid.isEmpty ? ssid : bssid
        let sum = seed.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xFFFFFF }
        return Double(sum % 360) / 360
    }
    var color: Color {
        Color(hue: hue, saturation: isConnected ? 0.95 : 0.65, brightness: isConnected ? 1.0 : 0.85)
    }
    var signalColor: Color {
        switch rssi {
        case (-55)...:      return .green
        case (-67)..<(-55): return .yellow
        case (-75)..<(-67): return .orange
        default:            return .red
        }
    }
}

// MARK: - Ponto da curva espectral

struct CurvePoint: Identifiable {
    let id: String
    let netID: String
    let label: String
    let mhz: Double
    let rssi: Double
}

// MARK: - Grafico do analyzer

struct AnalyzerChart: View {
    let networks: [WifiNetwork]
    let band: Band

    private var points: [CurvePoint] {
        networks.flatMap { n in
            n.curve().enumerated().map { i, p in
                CurvePoint(id: "\(n.id)-\(i)", netID: n.id,
                           label: n.displaySSID, mhz: p.mhz, rssi: p.rssi)
            }
        }
    }

    private var colorScale: [String: Color] {
        Dictionary(networks.map { ($0.id, $0.color) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(
                    x: .value("Frequencia", p.mhz),
                    yStart: .value("Piso", -100),
                    yEnd: .value("Sinal", p.rssi),
                    series: .value("Rede", p.netID)
                )
                .foregroundStyle(by: .value("Rede", p.netID))
                .opacity(0.16)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Frequencia", p.mhz),
                    y: .value("Sinal", p.rssi),
                    series: .value("Rede", p.netID)
                )
                .foregroundStyle(by: .value("Rede", p.netID))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartForegroundStyleScale(range: networks.map(\.color))
        .chartLegend(.hidden)
        .chartYScale(domain: -100...(-10))
        .chartXScale(domain: band.range)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-100, -90, -80, -70, -60, -50, -40, -30, -20]) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("\(Int(d))").font(.caption2) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: band.tickChannels.map {
                ChannelPlan.centerFrequency(channel: $0, band: band)
            }) { v in
                AxisGridLine()
                AxisValueLabel {
                    if let mhz = v.as(Double.self),
                       let ch = band.tickChannels.first(where: {
                           abs(ChannelPlan.centerFrequency(channel: $0, band: band) - mhz) < 0.5
                       }) {
                        Text("\(ch)").font(.caption2)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            // Rotulo de cada rede no pico da sua curva.
            GeometryReader { geo in
                ForEach(networks) { n in
                    let xFrac = (n.centerMHz - band.range.lowerBound)
                        / (band.range.upperBound - band.range.lowerBound)
                    let yFrac = 1 - (Double(max(n.rssi, -100)) + 100) / 90
                    if xFrac >= 0, xFrac <= 1 {
                        Text(n.displaySSID)
                            .font(.caption2.weight(n.isConnected ? .bold : .regular))
                            .foregroundStyle(n.color)
                            .fixedSize()
                            .position(
                                x: geo.size.width * xFrac,
                                y: max(10, geo.size.height * yFrac - 10)
                            )
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Tabela de redes

struct NetworkTable: View {
    let networks: [WifiNetwork]
    let noiseFloor: Int

    var body: some View {
        Table(networks) {
            TableColumn("Rede") { n in
                HStack(spacing: 6) {
                    Circle().fill(n.color).frame(width: 8, height: 8)
                    Text(n.displaySSID)
                        .fontWeight(n.isConnected ? .bold : .regular)
                    if n.isConnected {
                        Text("conectada")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                }
            }
            TableColumn("Sinal") { n in
                HStack(spacing: 6) {
                    SignalBars(rssi: n.rssi)
                    Text("\(n.rssi) dBm").monospacedDigit().foregroundStyle(n.signalColor)
                }
            }
            TableColumn("SNR") { n in
                Text("\(n.snr(noiseFloor: noiseFloor)) dB").monospacedDigit()
            }
            TableColumn("Qualidade") { n in Text(n.qualityLabel) }
            TableColumn("Canal") { n in Text("\(n.channel)").monospacedDigit() }
            TableColumn("Largura") { n in Text(Describe.width(n.width)) }
            TableColumn("Banda") { n in Text(n.band.label) }
            TableColumn("Centro") { n in Text("\(Int(n.centerMHz)) MHz").monospacedDigit() }
            TableColumn("Seguranca") { n in Text(n.security) }
            TableColumn("BSSID") { n in Text(n.bssid).font(.caption).monospaced() }
        }
    }
}

struct SignalBars: View {
    let rssi: Int
    private var level: Int {
        switch rssi {
        case (-55)...:      return 4
        case (-67)..<(-55): return 3
        case (-75)..<(-67): return 2
        case (-85)..<(-75): return 1
        default:            return 0
        }
    }
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.22))
                    .frame(width: 3, height: 4 + CGFloat(i) * 3)
            }
        }
        .frame(height: 13, alignment: .bottom)
    }
}

// MARK: - Tela de banda

struct BandScreen: View {
    let band: Band
    let scanner: WifiScanner

    private var nets: [WifiNetwork] { scanner.networks(in: band) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if nets.isEmpty {
                ContentUnavailableView {
                    Label("Nenhuma rede em \(band.label)", systemImage: "wifi.slash")
                } description: {
                    Text(band == .ghz6
                         ? "Nenhuma rede 6 GHz por perto, ou este Mac nao suporta Wi-Fi 6E."
                         : "Nenhuma rede detectada nesta banda.")
                }
            } else {
                AnalyzerChart(networks: nets, band: band)
                    .frame(minHeight: 260)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                HStack {
                    Text("Frequencia (canal)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(nets.count) redes").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                Divider()
                NetworkTable(networks: nets, noiseFloor: scanner.noiseFloor)
            }
        }
    }
}

// MARK: - Historico de sinal

struct HistoryScreen: View {
    let scanner: WifiScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = scanner.connected ?? scanner.networks.first(where: \.isConnected) {
                Text(c.displaySSID).font(.title2.bold())
            }
            Text("Sinal e SNR da rede conectada, amostrados a cada segundo. Caminhe pela casa para mapear a cobertura.")
                .font(.caption).foregroundStyle(.secondary)

            if scanner.history.isEmpty {
                ContentUnavailableView("Coletando amostras...", systemImage: "waveform.path.ecg")
            } else {
                Chart(scanner.history) { s in
                    LineMark(x: .value("Hora", s.time), y: .value("RSSI", s.rssi))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Hora", s.time),
                             yStart: .value("Piso", -100),
                             yEnd: .value("RSSI", s.rssi))
                        .foregroundStyle(.blue.opacity(0.12))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: -100...(-10))
                .frame(minHeight: 180)

                Text("SNR (dB)").font(.caption).foregroundStyle(.secondary)
                Chart(scanner.history) { s in
                    LineMark(x: .value("Hora", s.time), y: .value("SNR", s.snr))
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...80)
                .frame(minHeight: 120)

                HStack(spacing: 20) {
                    if let last = scanner.history.last {
                        Stat("Agora", "\(last.rssi) dBm")
                        Stat("SNR", "\(last.snr) dB")
                    }
                    let rssis = scanner.history.map(\.rssi)
                    if let mn = rssis.min(), let mx = rssis.max() {
                        Stat("Min", "\(mn) dBm")
                        Stat("Max", "\(mx) dBm")
                        Stat("Media", "\(rssis.reduce(0, +) / rssis.count) dBm")
                    }
                    Spacer()
                    Button("Limpar") { scanner.clearHistory() }
                }
                .font(.caption)
            }
        }
        .padding()
    }
}

// MARK: - Congestao

struct CongestionScreen: View {
    let scanner: WifiScanner
    @State private var band: Band = .ghz24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Banda", selection: $band) {
                ForEach(Band.allCases) { b in Text(b.label).tag(b) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let data = scanner.congestion(in: band)
            if data.isEmpty {
                ContentUnavailableView("Sem redes em \(band.label)", systemImage: "chart.bar")
            } else {
                Text("Redes por canal").font(.caption).foregroundStyle(.secondary)
                Chart(data, id: \.channel) { row in
                    BarMark(
                        x: .value("Canal", "\(row.channel)"),
                        y: .value("Redes", row.count)
                    )
                    .foregroundStyle(by: .value("Melhor sinal", row.bestRSSI))
                    .annotation(position: .top) {
                        Text("\(row.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .chartForegroundStyleScale(range: Gradient(colors: [.red, .orange, .green]))
                .chartLegend(.hidden)
                .frame(minHeight: 200)
            }

            if band == .ghz24 {
                Divider()
                Text("Canais recomendados em 2.4 GHz")
                    .font(.headline)
                Text("Apenas 1, 6 e 11 nao se sobrepoem. Menor pontuacao = menos interferencia.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(Array(scanner.recommended24().enumerated()), id: \.offset) { i, r in
                        VStack(spacing: 4) {
                            Text("Canal \(r.channel)").font(.headline)
                            Text("\(r.score)").font(.title3.monospacedDigit())
                                .foregroundStyle(i == 0 ? .green : .secondary)
                            if i == 0 {
                                Text("melhor").font(.caption2).foregroundStyle(.green)
                            }
                        }
                        .frame(width: 92)
                        .padding(.vertical, 10)
                        .background(i == 0 ? Color.green.opacity(0.10) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Visao geral

struct OverviewScreen: View {
    let scanner: WifiScanner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let c = scanner.connected {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "wifi").foregroundStyle(.tint)
                                Text(c.displaySSID).font(.title2.bold())
                                Spacer()
                                Text(c.qualityLabel)
                                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(c.signalColor.opacity(0.2), in: Capsule())
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
                                      alignment: .leading, spacing: 12) {
                                Stat("Sinal", "\(c.rssi) dBm")
                                Stat("Ruido", "\(scanner.noiseFloor) dBm")
                                Stat("SNR", "\(c.snr(noiseFloor: scanner.noiseFloor)) dB")
                                Stat("Canal", "\(c.channel)")
                                Stat("Banda", c.band.label)
                                Stat("Largura", Describe.width(c.width))
                                Stat("Centro", "\(Int(c.centerMHz)) MHz")
                                Stat("Seguranca", c.security)
                            }
                            Text("BSSID \(c.bssid)   ·   interface \(scanner.interfaceName)")
                                .font(.caption).foregroundStyle(.secondary).monospaced()
                        }
                        .padding(6)
                    } label: {
                        Label("Rede conectada", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } else {
                    GroupBox {
                        Label(scanner.powerOn ? "Wi-Fi ligado, sem conexao" : "Wi-Fi desligado",
                              systemImage: scanner.powerOn ? "wifi.exclamationmark" : "wifi.slash")
                        .padding(6)
                    }
                }

                GroupBox {
                    HStack(spacing: 0) {
                        ForEach(Band.allCases) { b in
                            VStack(spacing: 4) {
                                Text("\(scanner.bandCounts()[b] ?? 0)")
                                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                                Text(b.label).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 4) {
                            Text("\(scanner.networks.count)")
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tint)
                            Text("total").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("Redes por banda", systemImage: "chart.bar.doc.horizontal")
                }

                if !scanner.history.isEmpty {
                    GroupBox {
                        Chart(scanner.history.suffix(120)) { s in
                            LineMark(x: .value("t", s.time), y: .value("RSSI", s.rssi))
                                .foregroundStyle(.blue)
                                .interpolationMethod(.monotone)
                        }
                        .chartYScale(domain: -100...(-10))
                        .chartXAxis(.hidden)
                        .frame(height: 90)
                        .padding(.vertical, 4)
                    } label: {
                        Label("Sinal nos ultimos 2 minutos", systemImage: "waveform.path.ecg")
                    }
                }
            }
            .padding()
        }
    }
}

struct Stat: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.medium)).monospacedDigit()
        }
    }
}
