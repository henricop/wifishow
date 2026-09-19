import SwiftUI
import Charts
import CoreWLAN

// MARK: - Stable per-network color (derived from BSSID, not hashValue)

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

// MARK: - Spectral curve point

struct CurvePoint: Identifiable {
    let id: String
    let netID: String
    let label: String
    let mhz: Double
    let rssi: Double
}

// MARK: - Analyzer chart

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
                    x: .value("Frequency", p.mhz),
                    yStart: .value("Floor", -100),
                    yEnd: .value("Signal", p.rssi),
                    series: .value("Network", p.netID)
                )
                .foregroundStyle(by: .value("Network", p.netID))
                .opacity(0.16)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Frequency", p.mhz),
                    y: .value("Signal", p.rssi),
                    series: .value("Network", p.netID)
                )
                .foregroundStyle(by: .value("Network", p.netID))
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
            // Label for each network at the peak of its curve.
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

// MARK: - Network table

struct NetworkTable: View {
    let networks: [WifiNetwork]
    let noiseFloor: Int

    var body: some View {
        Table(networks) {
            TableColumn("Network") { n in
                HStack(spacing: 6) {
                    Circle().fill(n.color).frame(width: 8, height: 8)
                    Text(n.displaySSID)
                        .fontWeight(n.isConnected ? .bold : .regular)
                    if n.isConnected {
                        Text("connected")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                }
            }
            TableColumn("Signal") { n in
                HStack(spacing: 6) {
                    SignalBars(rssi: n.rssi)
                    Text("\(n.rssi) dBm").monospacedDigit().foregroundStyle(n.signalColor)
                }
            }
            TableColumn("SNR") { n in
                Text("\(n.snr(noiseFloor: noiseFloor)) dB").monospacedDigit()
            }
            TableColumn("Quality") { n in Text(n.qualityLabel) }
            TableColumn("Channel") { n in Text("\(n.channel)").monospacedDigit() }
            TableColumn("Width") { n in Text(Describe.width(n.width)) }
            TableColumn("Band") { n in Text(n.band.label) }
            TableColumn("Center") { n in Text("\(Int(n.centerMHz)) MHz").monospacedDigit() }
            TableColumn("Security") { n in Text(n.security) }
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

// MARK: - Band screen

struct BandScreen: View {
    let band: Band
    let scanner: WifiScanner

    private var nets: [WifiNetwork] { scanner.networks(in: band) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if nets.isEmpty {
                ContentUnavailableView {
                    Label("No networks on \(band.label)", systemImage: "wifi.slash")
                } description: {
                    Text(band == .ghz6
                         ? "No 6 GHz networks nearby, or this Mac does not support Wi-Fi 6E."
                         : "No networks detected on this band.")
                }
            } else {
                AnalyzerChart(networks: nets, band: band)
                    .frame(minHeight: 260)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                HStack {
                    Text("Frequency (channel)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(nets.count) networks").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

                Divider()
                NetworkTable(networks: nets, noiseFloor: scanner.noiseFloor)
            }
        }
    }
}

// MARK: - Signal history

struct HistoryScreen: View {
    let scanner: WifiScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let c = scanner.connected ?? scanner.networks.first(where: \.isConnected) {
                Text(c.displaySSID).font(.title2.bold())
            }
            Text("Signal and SNR of the connected network, sampled every second. Walk around your place to map coverage.")
                .font(.caption).foregroundStyle(.secondary)

            if scanner.history.isEmpty {
                ContentUnavailableView("Collecting samples...", systemImage: "waveform.path.ecg")
            } else {
                Chart(scanner.history) { s in
                    LineMark(x: .value("Time", s.time), y: .value("RSSI", s.rssi))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Time", s.time),
                             yStart: .value("Floor", -100),
                             yEnd: .value("RSSI", s.rssi))
                        .foregroundStyle(.blue.opacity(0.12))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: -100...(-10))
                .frame(minHeight: 180)

                Text("SNR (dB)").font(.caption).foregroundStyle(.secondary)
                Chart(scanner.history) { s in
                    LineMark(x: .value("Time", s.time), y: .value("SNR", s.snr))
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...80)
                .frame(minHeight: 120)

                HStack(spacing: 20) {
                    if let last = scanner.history.last {
                        Stat("Now", "\(last.rssi) dBm")
                        Stat("SNR", "\(last.snr) dB")
                    }
                    let rssis = scanner.history.map(\.rssi)
                    if let mn = rssis.min(), let mx = rssis.max() {
                        Stat("Min", "\(mn) dBm")
                        Stat("Max", "\(mx) dBm")
                        Stat("Avg", "\(rssis.reduce(0, +) / rssis.count) dBm")
                    }
                    Spacer()
                    Button("Clear") { scanner.clearHistory() }
                }
                .font(.caption)
            }
        }
        .padding()
    }
}

// MARK: - Congestion

struct CongestionScreen: View {
    let scanner: WifiScanner
    @State private var band: Band = .ghz24

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Band", selection: $band) {
                ForEach(Band.allCases) { b in Text(b.label).tag(b) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let data = scanner.congestion(in: band)
            if data.isEmpty {
                ContentUnavailableView("No networks on \(band.label)", systemImage: "chart.bar")
            } else {
                Text("Networks per channel").font(.caption).foregroundStyle(.secondary)
                Chart(data, id: \.channel) { row in
                    BarMark(
                        x: .value("Channel", "\(row.channel)"),
                        y: .value("Networks", row.count)
                    )
                    .foregroundStyle(by: .value("Best signal", row.bestRSSI))
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
                Text("Recommended 2.4 GHz channels")
                    .font(.headline)
                Text("Only 1, 6 and 11 do not overlap. Lower score = less interference.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(Array(scanner.recommended24().enumerated()), id: \.offset) { i, r in
                        VStack(spacing: 4) {
                            Text("Channel \(r.channel)").font(.headline)
                            Text("\(r.score)").font(.title3.monospacedDigit())
                                .foregroundStyle(i == 0 ? .green : .secondary)
                            if i == 0 {
                                Text("best").font(.caption2).foregroundStyle(.green)
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

// MARK: - Overview

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
                                Stat("Signal", "\(c.rssi) dBm")
                                Stat("Noise", "\(scanner.noiseFloor) dBm")
                                Stat("SNR", "\(c.snr(noiseFloor: scanner.noiseFloor)) dB")
                                Stat("Channel", "\(c.channel)")
                                Stat("Band", c.band.label)
                                Stat("Width", Describe.width(c.width))
                                Stat("Center", "\(Int(c.centerMHz)) MHz")
                                Stat("Security", c.security)
                            }
                            Text("BSSID \(c.bssid)   ·   interface \(scanner.interfaceName)")
                                .font(.caption).foregroundStyle(.secondary).monospaced()
                        }
                        .padding(6)
                    } label: {
                        Label("Connected network", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } else {
                    GroupBox {
                        Label(scanner.powerOn ? "Wi-Fi on, not connected" : "Wi-Fi is off",
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
                    Label("Networks per band", systemImage: "chart.bar.doc.horizontal")
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
                        Label("Signal over the last 2 minutes", systemImage: "waveform.path.ecg")
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
