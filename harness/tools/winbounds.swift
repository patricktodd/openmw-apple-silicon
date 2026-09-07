// Prints "<windowNumber> x,y,w,h" (screen points) of the first on-screen window owned by the given
// process: a numeric argument is matched against the owner PID, anything else against the owner name
// (case-insensitive). usage: winbounds <pid>|openmw
import Foundation
import CoreGraphics

let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "openmw"
let wantPid = Int(arg)
let owner = arg.lowercased()
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    exit(2)
}
for w in list {
    if let p = wantPid {
        guard let ownerPid = w[kCGWindowOwnerPID as String] as? Int, ownerPid == p else { continue }
    } else {
        guard let name = w[kCGWindowOwnerName as String] as? String, name.lowercased() == owner else { continue }
    }
    guard let num = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: Any],
          let x = b["X"] as? Double, let y = b["Y"] as? Double,
          let wd = b["Width"] as? Double, let ht = b["Height"] as? Double, wd > 200, ht > 200 else { continue }
    print("\(num) \(Int(x)),\(Int(y)),\(Int(wd)),\(Int(ht))")
    exit(0)
}
exit(1)
