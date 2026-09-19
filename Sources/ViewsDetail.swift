import SwiftUI
import Charts

// MARK: - Teste de velocidade

struct SpeedScreen: View {
    let runner: SpeedTestRunner

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch runner.state {
                case .idle:
                    idleCard
                case .running:
                    runningCard
                case .done(let r):
                    resultCards(r)
                    explanation(r)
                case .failed(let msg):
                    failureCard(msg)
                }

                if runner.history.count > 1 {
                    historySection
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Teste de velocidade").font(.title2.bold())
            Text("Usa o networkquality, a ferramenta nativa do macOS. Mede banda e responsividade sob carga — o teste leva cerca de 35 segundos.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var idleCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "speedometer")
                .font(.system(size: 42)).foregroundStyle(.tint)
            Text("Pronto para medir sua conexão")
                .font(.headline)
            Button {
                runner.run()
            } label: {
                Label("Iniciar teste", systemImage: "play.fill")
                    .frame(width: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var runningCard: some View {
        VStack(spacing: 14) {
            ProgressView(value: runner.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 380)
            Text(phaseLabel)
                .font(.headline)
            Text("\(Int(runner.elapsed))s de ~\(Int(runner.expectedDuration))s")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button("Cancelar") { runner.cancel() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var phaseLabel: String {
        switch runner.elapsed {
        case ..<3:   return "Conectando ao servidor..."
        case 3..<20: return "Medindo capacidade..."
        default:     return "Medindo responsividade sob carga..."
        }
    }

    private func resultCards(_ r: SpeedResult) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                MetricCard(icon: "arrow.down.circle.fill", color: .blue,
                           title: "Download",
                           value: String(format: "%.1f", r.downloadMbps), unit: "Mbps")
                MetricCard(icon: "arrow.up.circle.fill", color: .green,
                           title: "Upload",
                           value: String(format: "%.1f", r.uploadMbps), unit: "Mbps")
            }
            HStack(spacing: 12) {
                MetricCard(icon: "timer", color: .orange,
                           title: "Latência (RTT)",
                           value: String(format: "%.0f", r.baseRttMs), unit: "ms",
                           caption: r.latencyLabel)
                MetricCard(icon: "waveform.path.ecg", color: .purple,
                           title: "Responsividade",
                           value: String(format: "%.0f", r.responsiveness), unit: "RPM",
                           caption: r.responsivenessLabel)
            }

            HStack {
                Button { runner.run() } label: {
                    Label("Testar de novo", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text(r.date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func explanation(_ r: SpeedResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            InfoRow(title: "O que é responsividade (RPM)",
                    text: "Roundtrips Per Minute mede quantas idas e voltas a rede consegue fazer por minuto **enquanto está saturada**. Quanto maior, melhor. É a métrica que explica por que uma conexão de 500 Mbps ainda trava numa chamada de vídeo.")
            InfoRow(title: "Seu resultado", text: r.responsivenessHint)
            InfoRow(title: "Latência (RTT)",
                    text: "Tempo de ida e volta até o servidor com a rede ociosa. Abaixo de 50 ms é bom, acima de 100 ms atrapalha jogos e chamadas.")

            GroupBox {
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("Servidor", value: r.testEndpoint)
                    LabeledContent("Interface", value: r.interfaceName)
                    LabeledContent("Duração", value: String(format: "%.0f s", r.durationSec))
                    LabeledContent("Transferido",
                                   value: "↓ \(bytes(r.dlBytes))  ↑ \(bytes(r.ulBytes))")
                    LabeledContent("Sistema", value: r.osVersion)
                }
                .font(.caption).monospacedDigit()
                .padding(4)
            } label: {
                Label("Detalhes da medição", systemImage: "info.circle")
            }
        }
    }

    private func failureCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34)).foregroundStyle(.orange)
            Text("O teste não pôde ser concluído").font(.headline)
            Text(msg).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Tentar de novo") { runner.run() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Testes desta sessão").font(.headline)
            Chart(runner.history.reversed()) { r in
                BarMark(x: .value("Hora", r.date, unit: .second),
                        y: .value("Mbps", r.downloadMbps))
                .foregroundStyle(.blue)
                .position(by: .value("Tipo", "Download"))
                BarMark(x: .value("Hora", r.date, unit: .second),
                        y: .value("Mbps", r.uploadMbps))
                .foregroundStyle(.green)
                .position(by: .value("Tipo", "Upload"))
            }
            .frame(height: 140)

            ForEach(runner.history) { r in
                HStack {
                    Text(r.date, style: .time).foregroundStyle(.secondary)
                    Spacer()
                    Text("↓ \(String(format: "%.1f", r.downloadMbps))")
                    Text("↑ \(String(format: "%.1f", r.uploadMbps))")
                    Text("\(Int(r.baseRttMs)) ms")
                    Text("\(Int(r.responsiveness)) RPM")
                }
                .font(.caption.monospacedDigit())
            }
        }
    }

    private func bytes(_ n: Int) -> String {
        let mb = Double(n) / 1_048_576
        return mb >= 1024
            ? String(format: "%.2f GB", mb / 1024)
            : String(format: "%.0f MB", mb)
    }
}

struct MetricCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            if let c = caption {
                Text(c).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct InfoRow: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(.init(text)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detalhes do Wi-Fi

struct WifiDetailsScreen: View {
    @State private var details = InterfaceDetails.capture()
    @State private var refresher: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.ssid == "-" ? "Sem conexão" : details.ssid)
                        .font(.title2.bold())
                    Text("Tudo que o macOS expõe sobre a rede conectada. Clique no ícone de cada linha para entender a métrica.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                ForEach(DetailsBuilder.categories(details)) { cat in
                    GroupBox {
                        VStack(spacing: 0) {
                            ForEach(Array(cat.items.enumerated()), id: \.element.id) { i, item in
                                DetailRow(item: item)
                                if i < cat.items.count - 1 { Divider() }
                            }
                        }
                        .padding(.vertical, 2)
                    } label: {
                        Label(cat.title, systemImage: cat.icon)
                    }
                }
            }
            .padding()
        }
        .task {
            refresher = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let fresh = await Task.detached { InterfaceDetails.capture() }.value
                    await MainActor.run { details = fresh }
                }
            }
        }
        .onDisappear { refresher?.cancel() }
    }
}

struct DetailRow: View {
    let item: DetailItem
    @State private var showInfo = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.key)
                .font(.callout)
                .frame(width: 190, alignment: .leading)

            Text(item.value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .textSelection(.enabled)

            Spacer(minLength: 8)

            Button { showInfo.toggle() } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showInfo, arrowEdge: .trailing) {
                Text(item.explanation)
                    .font(.callout)
                    .padding(14)
                    .frame(width: 330)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}
