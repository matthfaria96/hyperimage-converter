// Prints the window numbers of the app's visible normal-level windows (main window and sheets), one per line.
// Used by ui-smoke.sh with REAL=1 to capture real renders (Liquid Glass included) via `screencapture -l`.
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "HyperImage" && (w["kCGWindowLayer"] as? Int) == 0 {
    print(w["kCGWindowNumber"] as! Int)
}
