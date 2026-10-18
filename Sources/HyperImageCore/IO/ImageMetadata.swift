import Foundation
import ImageIO

/// The EXIF/TIFF/GPS facts the text variables can print, already formatted.
public struct ImageMetadata: Equatable, Sendable {
    public var make = ""
    public var model = ""
    public var software = ""
    public var dateTaken: Date?
    public var comment = ""
    public var exposureTime = ""
    public var exposureProgram = ""
    public var exposureBias = ""
    public var fNumber = ""
    public var maxAperture = ""
    public var iso = ""
    public var flash = ""
    public var focalLength = ""
    public var focalLength35mm = ""
    public var meteringMode = ""
    public var lensModel = ""
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var dpiX: Double?
    public var dpiY: Double?
    public var jpegQuality: Int?

    public init() {}

    public init(properties: [CFString: Any]) {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifAux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        make = Self.string(tiff[kCGImagePropertyTIFFMake])
        model = Self.string(tiff[kCGImagePropertyTIFFModel])
        software = Self.string(tiff[kCGImagePropertyTIFFSoftware])
        let rawDate = exif[kCGImagePropertyExifDateTimeOriginal] ?? tiff[kCGImagePropertyTIFFDateTime]
        dateTaken = (rawDate as? String).flatMap(Self.exifDate)
        comment = Self.string(exif[kCGImagePropertyExifUserComment])
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            exposureTime = t < 1 ? "1/\(Int((1 / t).rounded()))s" : String(format: "%.1fs", t)
        }
        exposureProgram = Self.exposurePrograms[exif[kCGImagePropertyExifExposureProgram] as? Int ?? -1] ?? ""
        if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double { exposureBias = String(format: "%+.1f EV", bias) }
        if let f = exif[kCGImagePropertyExifFNumber] as? Double { fNumber = String(format: "F%.1f", f) }
        if let apex = exif[kCGImagePropertyExifMaxApertureValue] as? Double { maxAperture = String(format: "F%.1f", pow(2, apex / 2)) }
        if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = isoValues.first { iso = "ISO \(first)" }
        if let flashValue = exif[kCGImagePropertyExifFlash] as? Int {
            flash = flashValue & 1 == 1 ? String(localized: "Disparado") : String(localized: "Não disparado")
        }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double { focalLength = String(format: "%.0fmm", focal) }
        if let focal35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int { focalLength35mm = "\(focal35)mm" }
        meteringMode = Self.meteringModes[exif[kCGImagePropertyExifMeteringMode] as? Int ?? -1] ?? ""
        lensModel = Self.string(exif[kCGImagePropertyExifLensModel] ?? exifAux[kCGImagePropertyExifAuxLensModel])
        latitude = Self.coordinate(gps[kCGImagePropertyGPSLatitude], ref: gps[kCGImagePropertyGPSLatitudeRef], negative: "S")
        longitude = Self.coordinate(gps[kCGImagePropertyGPSLongitude], ref: gps[kCGImagePropertyGPSLongitudeRef], negative: "W")
        altitude = gps[kCGImagePropertyGPSAltitude] as? Double
        dpiX = properties[kCGImagePropertyDPIWidth] as? Double
        dpiY = properties[kCGImagePropertyDPIHeight] as? Double
    }

    private static func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)) ?? ""
    }

    private static func coordinate(_ value: Any?, ref: Any?, negative: String) -> Double? {
        guard let v = value as? Double else { return nil }
        return (ref as? String) == negative ? -v : v
    }

    static func exifDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    private static let exposurePrograms = [
        0: "Not defined", 1: "Manual", 2: "Normal program", 3: "Aperture priority", 4: "Shutter priority",
        5: "Creative program", 6: "Action program", 7: "Portrait mode", 8: "Landscape mode",
    ]

    private static let meteringModes = [
        0: "Unknown", 1: "Average", 2: "Center weighted average", 3: "Spot", 4: "Multi-spot", 5: "Pattern", 6: "Partial",
    ]
}
