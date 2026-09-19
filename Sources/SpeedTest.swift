import Foundation
import Observation

// MARK: - Teste de velocidade
//
// Usa o /usr/bin/networkquality, a ferramenta nativa do macOS. Alem de banda,
// ela mede *responsividade* (RPM) sob carga — que e o que realmente explica
// chamada de video travando numa conexao "rapida".
//
// Sem servidor proprio: o binario da Apple fala com o edge mais proximo.

struct SpeedResult: Identifiable, Codable {
    let id: UUID
    let date: Date
    let downloadBps: Double
    let uploadBps: Double
    let baseRttMs: Double
    let responsiveness: Double
    let interfaceName: String
    let osVersion: String
    let testEndpoint: String
    let durationSec: Double
    let dlBytes: Int
    let ulBytes: Int

    var downloadMbps: Double { downloadBps / 1_000_000 }
    var uploadMbps: Double   { uploadBps / 1_000_000 }

    /// Classificacao de responsividade segundo a escala da Apple.
    var responsivenessLabel: String {
        switch responsiveness {
        case ..<200:      return "Baixa"
        case 200..<1000:  return "Média"
        default:          return "Alta"
        }
    }

    var responsivenessHint: String {
        switch responsiveness {
        case ..<200:
            return "Sob carga a conexão engasga — sintoma clássico de bufferbloat. Chamadas de vídeo e jogos sofrem mesmo com banda sobrando."
        case 200..<1000:
            return "Comportamento aceitável sob carga. Chamadas de vídeo funcionam bem na maior parte do tempo."
        default:
            return "Excelente. A conexão continua responsiva mesmo saturada."
        }
    }

    var latencyLabel: String {
        switch baseRttMs {
        case ..<50:   return "Boa"
        case 50..<100: return "Aceitável"
        default:      return "Ruim"
        }
    }
}

// MARK: - Schema real do `networkquality -c`

struct NQOutput: Decodable {
    let base_rtt: Double?
    let dl_throughput: Double?
    let ul_throughput: Double?
    let responsiveness: Double?
    let interface_name: String?
    let os_version: String?
    let test_endpoint: String?
    let start_date: String?
    let end_date: String?
    let dl_bytes_transferred: Int?
    let ul_bytes_transferred: Int?
    let dl_phase_duration: Double?
}

extension SpeedResult {
    /// Converte a saida bruta do `networkquality -c` em um resultado.
    /// Separado da execucao do processo para poder ser testado offline.
    static func parse(_ data: Data) throws -> SpeedResult {
        let nq = try JSONDecoder().decode(NQOutput.self, from: data)
        guard let dl = nq.dl_throughput, let ul = nq.ul_throughput else {
            throw SpeedTestError.badOutput
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")

        let start = nq.start_date.flatMap(fmt.date(from:))
        let end   = nq.end_date.flatMap(fmt.date(from:))
        let dur   = (start != nil && end != nil)
            ? end!.timeIntervalSince(start!)
            : (nq.dl_phase_duration ?? 0)

        return SpeedResult(
            id: UUID(),
            date: end ?? Date(),
            downloadBps: dl,
            uploadBps: ul,
            baseRttMs: nq.base_rtt ?? 0,
            responsiveness: nq.responsiveness ?? 0,
            interfaceName: nq.interface_name ?? "-",
            osVersion: nq.os_version ?? "-",
            testEndpoint: nq.test_endpoint ?? "-",
            durationSec: dur,
            dlBytes: nq.dl_bytes_transferred ?? 0,
            ulBytes: nq.ul_bytes_transferred ?? 0
        )
    }
}

enum SpeedTestError: LocalizedError {
    case unavailable
    case failed(code: Int32, message: String)
    case badOutput
    case decoding(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "A ferramenta networkquality não está disponível neste macOS."
        case .failed(let code, let msg):
            return msg.isEmpty ? "O teste falhou (código \(code))." : "O teste falhou: \(msg)"
        case .badOutput:
            return "O teste devolveu uma resposta inesperada."
        case .decoding(let d):
            return "Não foi possível ler o resultado: \(d)"
        case .offline:
            return "Sem conexão com a internet."
        }
    }
}

enum SpeedTestState {
    case idle
    case running(started: Date)
    case done(SpeedResult)
    case failed(String)
}

@Observable
@MainActor
final class SpeedTestRunner {

    private(set) var state: SpeedTestState = .idle
    private(set) var history: [SpeedResult] = []
    private(set) var elapsed: TimeInterval = 0

    private var task: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// O teste da Apple leva cerca de 35s; usado so para a barra de progresso.
    let expectedDuration: TimeInterval = 36

    var progress: Double {
        min(elapsed / expectedDuration, 0.98)
    }

    func run() {
        guard !isRunning else { return }
        let started = Date()
        state = .running(started: started)
        elapsed = 0

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    guard let self, self.isRunning else { return }
                    self.elapsed = Date().timeIntervalSince(started)
                }
            }
        }

        task = Task { [weak self] in
            let outcome = await Self.execute()
            await MainActor.run {
                guard let self else { return }
                self.ticker?.cancel(); self.ticker = nil
                switch outcome {
                case .success(let r):
                    self.state = .done(r)
                    self.history.insert(r, at: 0)
                    if self.history.count > 20 { self.history.removeLast() }
                case .failure(let e):
                    self.state = .failed(e.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        task?.cancel();   task = nil
        ticker?.cancel(); ticker = nil
        state = .idle
        elapsed = 0
    }

    // MARK: Execucao do processo

    private nonisolated static func execute() async -> Result<SpeedResult, SpeedTestError> {
        await Task.detached(priority: .userInitiated) { () -> Result<SpeedResult, SpeedTestError> in
            let tool = "/usr/bin/networkquality"
            guard FileManager.default.isExecutableFile(atPath: tool) else {
                return .failure(.unavailable)
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: tool)
            proc.arguments = ["-c"]                      // saida em JSON

            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err

            do { try proc.run() } catch {
                return .failure(.failed(code: -1, message: error.localizedDescription))
            }

            // Ler antes de esperar: o pipe tem buffer limitado e a saida e grande.
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            guard proc.terminationStatus == 0 else {
                let msg = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if msg.localizedCaseInsensitiveContains("offline")
                    || msg.localizedCaseInsensitiveContains("network is down") {
                    return .failure(.offline)
                }
                return .failure(.failed(code: proc.terminationStatus, message: msg))
            }

            guard !outData.isEmpty else { return .failure(.badOutput) }

            do {
                return .success(try SpeedResult.parse(outData))
            } catch let e as SpeedTestError {
                return .failure(e)
            } catch {
                return .failure(.decoding(String(describing: error)))
            }
        }.value
    }
}
