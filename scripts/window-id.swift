// Prints the window number of the largest on-screen HyperImage window (the smallest with the argument "smallest").
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0["kCGWindowOwnerName"] as? String) == "HyperImage" }
let smallest = CommandLine.arguments.dropFirst().first == "smallest"
let best = windows.filter { (($0["kCGWindowBounds"] as? [String: Double])?["Height"] ?? 0) > 100 }.max { a, b in
    let area = { (w: [String: Any]) -> Double in
        let b = w["kCGWindowBounds"] as? [String: Double] ?? [:]
        return (b["Width"] ?? 0) * (b["Height"] ?? 0)
    }
    return smallest ? area(a) > area(b) : area(a) < area(b)
}
print(best?["kCGWindowNumber"] ?? 0)
