// Prints the window number of the largest on-screen HyperImage window.
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0["kCGWindowOwnerName"] as? String) == "HyperImage" }
let best = windows.max { a, b in
    let area = { (w: [String: Any]) -> Double in
        let b = w["kCGWindowBounds"] as? [String: Double] ?? [:]
        return (b["Width"] ?? 0) * (b["Height"] ?? 0)
    }
    return area(a) < area(b)
}
print(best?["kCGWindowNumber"] ?? 0)
