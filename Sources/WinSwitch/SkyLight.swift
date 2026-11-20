import Foundation
import CoreGraphics
import ApplicationServices

typealias CGSConnectionID = Int32

/// Private SkyLight (CGS/SLS) APIs, resolved lazily via dlopen/dlsym so a missing
/// symbol on a future macOS release degrades gracefully instead of crashing.
/// These are the same undocumented entry points AltTab and yabai rely on.
enum SkyLight {
    private static let skyLightHandle =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let hiServicesHandle =
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY)

    private static func sym<T>(_ name: String, _ type: T.Type,
                               from handle: UnsafeMutableRawPointer? = skyLightHandle) -> T? {
        guard let handle, let p = dlsym(handle, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    typealias MainConnectionID = @convention(c) () -> CGSConnectionID
    static let mainConnectionID = sym("SLSMainConnectionID", MainConnectionID.self)

    typealias GetActiveSpace = @convention(c) (CGSConnectionID) -> UInt64
    static let getActiveSpace = sym("SLSGetActiveSpace", GetActiveSpace.self)

    // Space a given window lives on (0/1 when unknown or minimized).
    typealias GetWindowWorkspace = @convention(c) (CGSConnectionID, UInt32, UnsafeMutablePointer<UInt64>) -> Int32
    static let getWindowWorkspace = sym("CGSGetWindowWorkspace", GetWindowWorkspace.self)

    typealias WindowCopyWorkspaceID = @convention(c) (CGSConnectionID, UInt32) -> UInt64
    static let windowCopyWorkspaceID = sym("SLSWindowCopyWorkspaceID", WindowCopyWorkspaceID.self)

    typealias CopyManagedDisplaySpaces = @convention(c) (CGSConnectionID) -> Unmanaged<CFArray>?
    static let copyManagedDisplaySpaces = sym("CGSCopyManagedDisplaySpaces", CopyManagedDisplaySpaces.self)

    // Switch the visible space on a display (animated space transition).
    typealias ManagedDisplaySetCurrentSpace = @convention(c) (CGSConnectionID, CFString, UInt64) -> Int32
    static let managedDisplaySetCurrentSpace = sym("CGSManagedDisplaySetCurrentSpace", ManagedDisplaySetCurrentSpace.self)

    // Pull window(s) onto a space — the trick used to summon windows from other spaces.
    typealias MoveWindowsToManagedSpace = @convention(c) (CGSConnectionID, CFArray, UInt64) -> Int32
    static let moveWindowsToManagedSpace = sym("SLSMoveWindowsToManagedSpace", MoveWindowsToManagedSpace.self)

    // Alternate space-move primitive on newer macOS releases.
    typealias SpaceAddRemoveWindows = @convention(c) (CGSConnectionID, UInt64, CFArray, CFArray) -> Int32
    static let spaceAddWindowsAndRemoveFromSpaces =
        sym("SLSSpaceAddWindowsAndRemoveFromSpaces", SpaceAddRemoveWindows.self)

    // Raise a window within the window server's ordering (fallback when AX is unavailable).
    typealias OrderWindow = @convention(c) (CGSConnectionID, UInt32, Int32, UInt32) -> Int32
    static let orderWindow = sym("SLSOrderWindow", OrderWindow.self)

    // Maps an AXUIElement window to its CGWindowID (undocumented but widely used).
    typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError
    static let axGetWindow = sym("_AXUIElementGetWindow", AXGetWindow.self, from: hiServicesHandle)

    static var cid: CGSConnectionID { mainConnectionID?() ?? 0 }
}
