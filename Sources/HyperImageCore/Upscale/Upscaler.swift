import CoreGraphics
import Foundation
import ImageIO

/// AI models bundled from Upscayl. Only models whose licences allow redistribution are included.
public enum UpscaleModel: String, Codable, CaseIterable, Sendable {
    case standard = "upscayl-standard-4x"
    case lite = "upscayl-lite-4x"
    case highFidelity = "high-fidelity-4x"
    case digitalArt = "digital-art-4x"

    public var title: String {
        switch self {
        case .standard: String(localized: "Padrão")
        case .lite: String(localized: "Rápido (Lite)")
        case .highFidelity: String(localized: "Alta fidelidade")
        case .digitalArt: String(localized: "Arte digital")
        }
    }

    public var help: String {
        switch self {
        case .standard: String(localized: "Bom para a maioria das fotos.")
        case .lite: String(localized: "Mais rápido, com um pouco menos de detalhe.")
        case .highFidelity: String(localized: "Preserva texturas e detalhes finos de fotos.")
        case .digitalArt: String(localized: "Ilustrações, desenhos e anime.")
        }
    }
}

public enum UpscaleFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg, webp

    public var outputFormat: OutputFormat {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .webp: .webp
        }
    }

    var cliName: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .webp: "webp"
        }
    }
}

public struct UpscaleSettings: Codable, Equatable, Sendable {
    public var model = UpscaleModel.standard
    /// Output scale: 2, 3 or 4.
    public var scale = 4
    public var format = UpscaleFormat.png
    /// Upscayl's compression (0 = best quality) for JPEG/WebP.
    public var compression = 0

    public init() {}
}

public enum UpscaleError: LocalizedError {
    case backendMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .backendMissing: String(localized: "O motor de IA (Upscayl) não foi encontrado no aplicativo.")
        case let .failed(message): String(localized: "Falha no AI Upscale: \(message)")
        }
    }
}

/// Runs the bundled `upscayl-bin` (Real-ESRGAN on the GPU) for one file at a time.
public struct Upscaler: Sendable {
    public let executable: URL
    public let modelsFolder: URL
    /// Where the per-run `hyperimage-upscale-*` work folder is created.
    /// nil = a replacement folder on the output's volume, so the final swap stays a same-volume rename.
    public let tempRoot: URL?

    public init(executable: URL, modelsFolder: URL, tempRoot: URL? = nil) {
        self.executable = executable
        self.modelsFolder = modelsFolder
        self.tempRoot = tempRoot
    }

    /// The copy inside the app bundle, or `HYPERIMAGE_UPSCAYL` (a folder holding upscayl-bin and models/) in tests.
    public static func bundled() -> Upscaler? {
        let fm = FileManager.default
        if let dir = ProcessInfo.processInfo.environment["HYPERIMAGE_UPSCAYL"] {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            return Upscaler(executable: folder.appendingPathComponent("upscayl-bin"), modelsFolder: folder.appendingPathComponent("models"))
        }
        guard let exec = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("upscayl-bin"),
              let models = Bundle.main.resourceURL?.appendingPathComponent("Upscayl/models"),
              fm.isExecutableFile(atPath: exec.path) else { return nil }
        return Upscaler(executable: exec, modelsFolder: models)
    }

    /// Upscales `input` into `output`. Inputs the backend cannot read (HEIC, TIFF, RAW…) go through a temporary PNG.
    /// `progress` receives 0…1. Cancelling the calling task terminates the process.
    public func upscale(_ input: URL, to output: URL, settings: UpscaleSettings,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let fm = FileManager.default
        let temp = try workFolder(near: output)
        defer { try? fm.removeItem(at: temp) }

        try Task.checkCancellation()
        let source: URL
        // The backend ignores EXIF orientation, so rotated photos are normalised through ImageLoader first.
        if ["jpg", "jpeg", "png", "webp"].contains(input.pathExtension.lowercased()), Self.orientation(of: input) == 1 {
            source = input
        } else {
            source = temp.appendingPathComponent("input.png")
            let loaded = try ImageLoader.load(input)
            guard let dest = CGImageDestinationCreateWithURL(source as CFURL, "public.png" as CFString, 1, nil) else {
                throw UpscaleError.failed(input.lastPathComponent)
            }
            CGImageDestinationAddImage(dest, loaded.image, nil)
            guard CGImageDestinationFinalize(dest) else { throw UpscaleError.failed(input.lastPathComponent) }
        }
        try Task.checkCancellation()
        // Written beside, then moved, so a cancelled run never leaves a half-written output.
        let partial = temp.appendingPathComponent("output.\(settings.format.cliName)")
        try await run(arguments: [
            "-i", source.path, "-o", partial.path,
            "-m", modelsFolder.path, "-n", settings.model.rawValue,
            "-s", String(min(4, max(2, settings.scale))),
            "-f", settings.format.cliName,
            "-c", String(min(100, max(0, settings.compression))),
        ], progress: progress)
        guard fm.fileExists(atPath: partial.path) else { throw UpscaleError.failed(String(localized: "nenhum arquivo gerado")) }
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Task.checkCancellation()
        // Swapped in atomically: the previous output is never deleted before the new one is in place.
        if fm.fileExists(atPath: output.path) {
            _ = try fm.replaceItemAt(output, withItemAt: partial)
        } else {
            try fm.moveItem(at: partial, to: output)
        }
    }

    /// Creates the per-run work folder: under `tempRoot` when set, otherwise on the output's volume.
    private func workFolder(near output: URL) throws -> URL {
        let fm = FileManager.default
        if tempRoot == nil, let replacement = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                           appropriateFor: Self.existingAncestor(of: output), create: true) {
            // Already unique and created; removed whole by the caller.
            return replacement
        }
        let base = tempRoot ?? fm.temporaryDirectory
        let temp = base.appendingPathComponent("hyperimage-upscale-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        return temp
    }

    /// The closest folder above `url` that already exists, used to pick the volume.
    static func existingAncestor(of url: URL) -> URL {
        var current = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: current.path), current.pathComponents.count > 1 {
            current = current.deletingLastPathComponent()
        }
        return current
    }

    private func run(arguments: [String], progress: @escaping @Sendable (Double) -> Void) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw UpscaleError.backendMissing }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let log = LogBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            // Complete lines only: a chunk can end in the middle of "42.50%".
            for line in log.appendLines(String(decoding: chunk, as: UTF8.self)) {
                if let value = Self.percentage(line) { progress(value / 100) }
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                    // A cancel that arrived before launch found no running process to stop.
                    if Task.isCancelled { process.terminate() }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            let tail = log.text.split(whereSeparator: \.isNewline).suffix(3).joined(separator: " ")
            throw UpscaleError.failed(tail.isEmpty ? "código \(process.terminationStatus)" : tail)
        }
    }
}

extension Upscaler {
    /// "42.50%" or "42.50" → 42.5; anything else → nil.
    static func percentage(_ line: Substring) -> Double? {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("%") { text.removeLast() }
        guard let value = Double(text), (0...100).contains(value) else { return nil }
        return value
    }

    static func orientation(of url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 1 }
        return p[kCGImagePropertyOrientation] as? Int ?? 1
    }
}

private final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    private var pending = ""

    /// Appends output and returns the lines it completed.
    func appendLines(_ s: String) -> [Substring] {
        lock.lock(); defer { lock.unlock() }
        storage += s
        if storage.count > 8000 { storage = String(storage.suffix(4000)) }
        pending += s
        // The backend redraws progress with carriage returns as well as newlines.
        let parts = pending.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" })
        pending = String(parts.last ?? "")
        return Array(parts.dropLast())
    }

    var text: String { lock.lock(); defer { lock.unlock() }; return storage }
}
