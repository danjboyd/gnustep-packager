// Prints the Apple Events permission status for automating Finder from the
// responsible process, without ever showing a consent prompt:
//   0      allowed
//   -1743  denied (errAEEventNotPermitted)
//   -1744  would ask the user (errAEEventWouldRequireUserConsent)
//   -600   Finder is not running (procNotFound)
import CoreServices
import Foundation

var target = AEAddressDesc()
let bundleID = Array("com.apple.finder".utf8)
_ = bundleID.withUnsafeBytes { bytes in
  AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress, bytes.count, &target)
}
let status = AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
AEDisposeDesc(&target)
print(status)
