import Foundation
import Observation

// MARK: - Speed test
//
// Uses /usr/bin/networkquality, the tool built into macOS. Beyond bandwidth it
// measures *responsiveness* (RPM) under load — which is what actually explains
// a video call stuttering on a "fast" connection.
//
// No server of our own: Apple's binary talks to the nearest edge.

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

    /// Responsiveness rating following Apple's scale.
    var responsivenessLabel: String {
        switch responsiveness {
        case ..<200:      return "Low"
        case 200..<1000:  return "Medium"
        default:          return "High"
        }
    }

    var responsivenessHint: String {
        switch responsiveness {
        case ..<200:
            return "The connection stalls under load — the classic symptom of bufferbloat. Video calls and games suffer even with bandwidth to spare."
        case 200..<1000:
            return "Acceptable behavior under load. Video calls work well most of the time."
        default:
            return "Excellent. The connection stays responsive even when saturated."
        }
    }

    var latencyLabel: String {
        switch baseRttMs {
        case ..<50:    return "Good"
        case 50..<100: return "Acceptable"
        default:       return "Poor"
        }
    }
}

// MARK: - Real schema of `networkquality -c`

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
    /// Converts the raw output of `networkquality -c` into a result.
    /// Kept separate from process execution so it can be tested offline.
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
            return "The networkquality tool is not available on this macOS."
        case .failed(let code, let msg):
            return msg.isEmpty ? "The test failed (exit code \(code))." : "The test failed: \(msg)"
        case .badOutput:
            return "The test returned an unexpected response."
        case .decoding(let d):
            return "Could not read the result: \(d)"
        case .offline:
            return "No internet connection."
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

    /// Apple's test takes about 35s; used only to drive the progress bar.
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

    // MARK: Process execution

    private nonisolated static func execute() async -> Result<SpeedResult, SpeedTestError> {
        await Task.detached(priority: .userInitiated) { () -> Result<SpeedResult, SpeedTestError> in
            let tool = "/usr/bin/networkquality"
            guard FileManager.default.isExecutableFile(atPath: tool) else {
                return .failure(.unavailable)
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: tool)
            proc.arguments = ["-c"]                      // JSON output

            let out = Pipe(), err = Pipe()
            proc.standardOutput = out
            proc.standardError = err

            do { try proc.run() } catch {
                return .failure(.failed(code: -1, message: error.localizedDescription))
            }

            // Read before waiting: the pipe buffer is limited and output is large.
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
