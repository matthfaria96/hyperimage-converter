import Foundation

/// Everything a text overlay may refer to.
public struct TextVariableContext: Sendable {
    public var fileURL: URL
    public var fileDate: Date
    public var imageSize: PixelSize
    public var metadata: ImageMetadata

    public init(fileURL: URL, fileDate: Date, imageSize: PixelSize, metadata: ImageMetadata) {
        self.fileURL = fileURL
        self.fileDate = fileDate
        self.imageSize = imageSize
        self.metadata = metadata
    }
}

/// Expands `$A`, `$C1`, `$H1`, `$GPS1`… in overlay text.
public enum TextVariables {
    public struct Variable: Sendable {
        public let token: String
        public let title: String
    }

    /// Menu entries for "Insert a Variable", in display order.
    public static let catalog: [Variable] = [
        .init(token: "$A", title: String(localized: "Largura da imagem")),
        .init(token: "$B", title: String(localized: "Altura da imagem")),
        .init(token: "$C1", title: String(localized: "Nome do arquivo (com extensão)")),
        .init(token: "$C2", title: String(localized: "Nome do arquivo (sem extensão)")),
        .init(token: "$C3", title: String(localized: "Caminho da pasta")),
        .init(token: "$D1", title: String(localized: "Data e hora do arquivo")),
        .init(token: "$D2", title: String(localized: "Ano do arquivo")),
        .init(token: "$D3", title: String(localized: "Mês do arquivo")),
        .init(token: "$D4", title: String(localized: "Dia do arquivo")),
        .init(token: "$D5", title: String(localized: "Hora do arquivo")),
        .init(token: "$D6", title: String(localized: "Minuto do arquivo")),
        .init(token: "$D7", title: String(localized: "Segundo do arquivo")),
        .init(token: "$E", title: String(localized: "Fabricante (EXIF)")),
        .init(token: "$F", title: String(localized: "Modelo (EXIF)")),
        .init(token: "$G", title: String(localized: "Software (EXIF)")),
        .init(token: "$H1", title: String(localized: "Data e hora da foto (EXIF)")),
        .init(token: "$H2", title: String(localized: "Ano da foto")),
        .init(token: "$H3", title: String(localized: "Mês da foto")),
        .init(token: "$H4", title: String(localized: "Dia da foto")),
        .init(token: "$H5", title: String(localized: "Hora da foto")),
        .init(token: "$H6", title: String(localized: "Minuto da foto")),
        .init(token: "$H7", title: String(localized: "Segundo da foto")),
        .init(token: "$I", title: String(localized: "Comentário")),
        .init(token: "$J", title: String(localized: "Tempo de exposição")),
        .init(token: "$K", title: String(localized: "Programa de exposição")),
        .init(token: "$L", title: String(localized: "Compensação de exposição")),
        .init(token: "$M", title: String(localized: "Número F")),
        .init(token: "$N", title: String(localized: "Abertura máxima")),
        .init(token: "$O", title: "ISO"),
        .init(token: "$P", title: String(localized: "Flash")),
        .init(token: "$Q", title: String(localized: "Distância focal")),
        .init(token: "$R", title: String(localized: "Equivalente 35 mm")),
        .init(token: "$S", title: String(localized: "Modo de medição")),
        .init(token: "$U", title: String(localized: "Modelo da lente")),
        .init(token: "$GPS1", title: String(localized: "GPS (latitude, longitude)")),
        .init(token: "$GPS2", title: String(localized: "GPS (graus/minutos/segundos)")),
        .init(token: "$GPS3", title: String(localized: "GPS (altitude)")),
    ]

    public static func expand(_ text: String, context: TextVariableContext) -> String {
        let values = valueTable(context)
        // Longest tokens first so "$GPS1" wins over "$G" and "$C1" over a bare "$C".
        let tokens = values.keys.sorted { $0.count > $1.count }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$", let token = tokens.first(where: { text[index...].hasPrefix($0) }) {
                output += values[token] ?? ""
                index = text.index(index, offsetBy: token.count)
            } else {
                output.append(text[index])
                index = text.index(after: index)
            }
        }
        return output
    }

    private static func valueTable(_ c: TextVariableContext) -> [String: String] {
        let m = c.metadata
        let taken = m.dateTaken ?? c.fileDate
        var table: [String: String] = [
            "$A": "\(c.imageSize.width)",
            "$B": "\(c.imageSize.height)",
            "$C1": c.fileURL.lastPathComponent,
            "$C2": c.fileURL.deletingPathExtension().lastPathComponent,
            "$C3": c.fileURL.deletingLastPathComponent().path,
            "$E": m.make, "$F": m.model, "$G": m.software, "$I": m.comment,
            "$J": m.exposureTime, "$K": m.exposureProgram, "$L": m.exposureBias, "$M": m.fNumber,
            "$N": m.maxAperture, "$O": m.iso, "$P": m.flash, "$Q": m.focalLength, "$R": m.focalLength35mm,
            "$S": m.meteringMode, "$U": m.lensModel,
            "$GPS1": gpsDecimal(m), "$GPS2": gpsDMS(m), "$GPS3": m.altitude.map { String(format: "%.0f m", $0) } ?? "",
        ]
        for (prefix, date) in [("$D", c.fileDate), ("$H", taken)] {
            for (n, part) in dateParts(date).enumerated() { table["\(prefix)\(n + 1)"] = part }
        }
        return table
    }

    static func dateParts(_ date: Date) -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let p = calendar.dateComponents(in: .current, from: date)
        let two = { (v: Int?) in String(format: "%02d", v ?? 0) }
        let full = String(format: "%04d-%02d-%02d  %02d:%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0, p.hour ?? 0, p.minute ?? 0)
        return [full, String(format: "%04d", p.year ?? 0), two(p.month), two(p.day), two(p.hour), two(p.minute), two(p.second)]
    }

    private static func gpsDecimal(_ m: ImageMetadata) -> String {
        guard let lat = m.latitude, let lon = m.longitude else { return "" }
        return String(format: "%.6f, %.6f", lat, lon)
    }

    private static func gpsDMS(_ m: ImageMetadata) -> String {
        guard let lat = m.latitude, let lon = m.longitude else { return "" }
        func dms(_ v: Double, _ pos: String, _ neg: String) -> String {
            let a = abs(v)
            let d = Int(a), mins = Int((a - Double(d)) * 60), s = (a - Double(d) - Double(mins) / 60) * 3600
            return String(format: "%d°%02d'%04.1f\"%@", d, mins, s, v < 0 ? neg : pos)
        }
        return "\(dms(lat, "N", "S")) \(dms(lon, "E", "W"))"
    }
}
