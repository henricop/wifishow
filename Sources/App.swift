import SwiftUI

enum Screen: String, CaseIterable, Identifiable, Hashable {
    case overview, ghz24, ghz5, ghz6, history, congestion, speed, details, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:   return "Visao geral"
        case .ghz24:      return "2.4 GHz"
        case .ghz5:       return "5 GHz"
        case .ghz6:       return "6 GHz"
        case .history:    return "Historico de sinal"
        case .congestion: return "Congestao de canais"
        case .speed:      return "Teste de velocidade"
        case .details:    return "Detalhes do Wi-Fi"
        case .all:        return "Todas as redes"
        }
    }

    var icon: String {
        switch self {
        case .overview:   return "square.grid.2x2"
        case .ghz24:      return "antenna.radiowaves.left.and.right"
        case .ghz5:       return "antenna.radiowaves.left.and.right"
        case .ghz6:       return "antenna.radiowaves.left.and.right"
        case .history:    return "waveform.path.ecg"
        case .congestion: return "chart.bar.xaxis"
        case .speed:      return "speedometer"
        case .details:    return "doc.text.magnifyingglass"
        case .all:        return "list.bullet"
        }
    }
}

struct RootView: View {
    @State private var scanner = WifiScanner()
    @State private var gate = LocationGate()
    @State private var speedTest = SpeedTestRunner()
    @State private var screen: Screen = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $screen) {
                Section("Analisar") {
                    row(.overview)
                    row(.ghz24, badge: scanner.bandCounts()[.ghz24])
                    row(.ghz5,  badge: scanner.bandCounts()[.ghz5])
                    row(.ghz6,  badge: scanner.bandCounts()[.ghz6])
                }
                Section("Monitorar") {
                    row(.history)
                    row(.congestion)
                    row(.speed)
                }
                Section("Dados") {
                    row(.details)
                    row(.all, badge: scanner.networks.count)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            Group {
                if !gate.isAuthorized {
                    permissionGate
                } else {
                    switch screen {
                    case .overview:   OverviewScreen(scanner: scanner)
                    case .ghz24:      BandScreen(band: .ghz24, scanner: scanner)
                    case .ghz5:       BandScreen(band: .ghz5,  scanner: scanner)
                    case .ghz6:       BandScreen(band: .ghz6,  scanner: scanner)
                    case .history:    HistoryScreen(scanner: scanner)
                    case .congestion: CongestionScreen(scanner: scanner)
                    case .speed:      SpeedScreen(runner: speedTest)
                    case .details:    WifiDetailsScreen()
                    case .all:        NetworkTable(networks: scanner.networks,
                                                   noiseFloor: scanner.noiseFloor)
                    }
                }
            }
            .navigationTitle(screen.title)
            .toolbar { toolbarContent }
        }
        .task {
            gate.request()
            scanner.start()
        }
    }

    private func row(_ s: Screen, badge: Int? = nil) -> some View {
        NavigationLink(value: s) {
            Label(s.title, systemImage: s.icon)
                .badge(badge ?? 0)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            HStack(spacing: 8) {
                Circle()
                    .fill(scanner.errorText == nil ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                if scanner.isScanning {
                    ProgressView().controlSize(.small)
                    Text("varrendo...").font(.caption).foregroundStyle(.secondary)
                } else if let t = scanner.lastScan {
                    Text(t, style: .time).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let e = scanner.errorText {
                    Text(e).font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(minWidth: 90, minHeight: 20)
        }
        ToolbarItem {
            Picker("Intervalo", selection: Binding(
                get: { scanner.interval },
                set: { scanner.interval = $0 }
            )) {
                Text("3s").tag(TimeInterval(3))
                Text("5s").tag(TimeInterval(5))
                Text("10s").tag(TimeInterval(10))
                Text("30s").tag(TimeInterval(30))
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Button { scanner.scanNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(scanner.isScanning)
            .keyboardShortcut("r")
            .help("Varrer agora (Cmd+R)")
        }
    }

    private var permissionGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 44)).foregroundStyle(.orange)
            Text("Localizacao necessaria").font(.title2.bold())
            Text(gate.message)
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Desde o macOS 14, o sistema so revela SSID e BSSID das redes vizinhas para apps com permissao de localizacao. Nada e enviado para lugar nenhum — o app nao acessa a rede.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack {
                Button("Pedir permissao") { gate.request() }
                    .buttonStyle(.borderedProminent)
                Button("Abrir Ajustes do sistema") { gate.openSettings() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

@main
struct WifiShowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands { SidebarCommands() }
    }
}
