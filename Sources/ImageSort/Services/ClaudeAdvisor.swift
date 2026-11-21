import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClaudeVerdict: Equatable, Sendable {
    /// 0-basert indeks i listen som ble sendt.
    var best: Int
    var ranking: [Int]
    var comment: String
}

enum ClaudeError: LocalizedError {
    case cliNotFound
    case failed(String)
    case timeout
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Fant ikke Claude Code (`claude`). Installer det fra claude.com/claude-code og logg inn med abonnementet ditt i Terminal (kjør `claude` én gang)."
        case .failed(let msg): return "Claude feilet: \(msg)"
        case .timeout: return "Claude brukte for lang tid (tidsavbrudd)."
        case .badResponse(let msg): return "Forsto ikke svaret fra Claude: \(msg)"
        }
    }
}

/// Spør Claude (via Claude Code-CLI og brukerens abonnement) om hvilket bilde som er best.
enum ClaudeAdvisor {
    static let maxImages = 12

    static func isAvailable() async -> Bool {
        let r = try? await runShell("command -v claude", env: [:], cwd: nil, timeout: 15)
        return (r?.status == 0) && !(r?.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func prompt(count: Int) -> String {
        let names = (1...count).map { "\($0).jpg" }.joined(separator: ", ")
        return """
        Du hjelper en forelder å rydde i bilder. I denne mappen ligger \(count) bilder av samme motiv: \(names).
        Les ALLE bildene med Read-verktøyet. Velg det ene bildet som er best å beholde.
        Vurder: skarphet/fokus på motivet, åpne øyne, ansiktsuttrykk og smil, komposisjon, lys og om motivet er helt med.
        Svar KUN med ett JSON-objekt, uten annen tekst:
        {"best": <nummer>, "ranking": [<nummer fra best til dårligst>], "comment": "<én kort setning på norsk om hvorfor>"}
        """
    }

    static func ask(about urls: [URL], model: String) async throws -> ClaudeVerdict {
        guard await isAvailable() else { throw ClaudeError.cliNotFound }
        let images = Array(urls.prefix(maxImages))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageSort-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (i, url) in images.enumerated() {
            guard let cg = ImageLoader.cgImage(url: url, maxPixel: 768) else { continue }
            let out = dir.appendingPathComponent("\(i + 1).jpg")
            if let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                CGImageDestinationFinalize(dest)
            }
        }

        let env = ["IMAGESORT_PROMPT": prompt(count: images.count), "IMAGESORT_MODEL": model]
        let cmd = #"claude -p "$IMAGESORT_PROMPT" --output-format json --allowedTools Read --model "$IMAGESORT_MODEL""#
        let r = try await runShell(cmd, env: env, cwd: dir, timeout: 240)
        guard r.status == 0 else {
            let msg = (r.stderr.isEmpty ? r.stdout : r.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClaudeError.failed(String(msg.prefix(400)))
        }
        return try parse(output: r.stdout, count: images.count)
    }

    /// Tolker JSON-utdata fra `claude -p --output-format json`.
    static func parse(output: String, count: Int) throws -> ClaudeVerdict {
        var text = output
        if let data = output.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if (obj["is_error"] as? Bool) == true {
                throw ClaudeError.failed((obj["result"] as? String) ?? "ukjent feil")
            }
            if let result = obj["result"] as? String { text = result }
        }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.badResponse(String(text.prefix(200)))
        }
        guard let best = (obj["best"] as? NSNumber)?.intValue, (1...count).contains(best) else {
            throw ClaudeError.badResponse("mangler gyldig \"best\"")
        }
        let ranking = ((obj["ranking"] as? [NSNumber]) ?? []).map { $0.intValue - 1 }.filter { (0..<count).contains($0) }
        return ClaudeVerdict(best: best - 1, ranking: ranking, comment: (obj["comment"] as? String) ?? "")
    }

    struct ShellResult { var status: Int32; var stdout: String; var stderr: String }

    /// Kjører en kommando i brukerens login-shell, slik at PATH fra terminalen gjelder også i GUI-appen.
    static func runShell(_ command: String, env: [String: String], cwd: URL?, timeout: TimeInterval) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", command]
            p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
            if let cwd { p.currentDirectoryURL = cwd }
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice

            let state = ShellState()
            // Les rørene fortløpende så prosessen ikke blokkerer på full buffer.
            out.fileHandleForReading.readabilityHandler = { h in state.appendOut(h.availableData) }
            err.fileHandleForReading.readabilityHandler = { h in state.appendErr(h.availableData) }

            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                state.appendOut(out.fileHandleForReading.readDataToEndOfFile())
                state.appendErr(err.fileHandleForReading.readDataToEndOfFile())
                if state.finish() {
                    if state.timedOut { cont.resume(throwing: ClaudeError.timeout) }
                    else { cont.resume(returning: state.result(status: proc.terminationStatus)) }
                }
            }
            do { try p.run() } catch {
                if state.finish() { cont.resume(throwing: error) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { state.timedOut = true; p.terminate() }
            }
        }
    }
}

private final class ShellState: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data(), errData = Data()
    private var finished = false
    var timedOut = false

    func appendOut(_ d: Data) { lock.lock(); outData.append(d); lock.unlock() }
    func appendErr(_ d: Data) { lock.lock(); errData.append(d); lock.unlock() }
    /// Returnerer true første gang den kalles.
    func finish() -> Bool { lock.lock(); defer { lock.unlock() }; if finished { return false }; finished = true; return true }
    func result(status: Int32) -> ClaudeAdvisor.ShellResult {
        lock.lock(); defer { lock.unlock() }
        return .init(status: status, stdout: String(decoding: outData, as: UTF8.self), stderr: String(decoding: errData, as: UTF8.self))
    }
}
