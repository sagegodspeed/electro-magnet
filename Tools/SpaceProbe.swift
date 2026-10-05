import AppKit
import Darwin

typealias MainConnection = @convention(c) () -> Int32
typealias CopyManaged = @convention(c) (Int32) -> Unmanaged<CFArray>?
typealias CopyWindowSpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
typealias SetCompat = @convention(c) (Int32, UInt64, Int32) -> Int32
typealias SetWorkspace = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32, Int32) -> Int32
typealias MoveManaged = @convention(c) (Int32, CFArray, UInt64) -> Void

let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)!
func symbol<T>(_ name: String, _: T.Type) -> T {
    guard let address = dlsym(handle, name) else { fatalError("Missing symbol: \(name)") }
    return unsafeBitCast(address, to: T.self)
}
let connection = symbol("SLSMainConnectionID", MainConnection.self)()
let copyManaged = symbol("SLSCopyManagedDisplaySpaces", CopyManaged.self)
let copySpaces = symbol("SLSCopySpacesForWindows", CopyWindowSpaces.self)
let setCompat = symbol("SLSSpaceSetCompatID", SetCompat.self)
let setWorkspace = symbol("SLSSetWindowListWorkspace", SetWorkspace.self)
let moveManaged = symbol("SLSMoveWindowsToManagedSpace", MoveManaged.self)
func moveBridged(_ window: UInt32, _ target: UInt64) -> AnyObject? {
    guard let cls = NSClassFromString("SLSBridgedMoveWindowsToManagedSpaceOperation"),
          let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
    let initializer = NSSelectorFromString("initWithWindows:spaceID:")
    let perform = NSSelectorFromString("performWithWMBridgeDelegate")
    guard allocated.responds(to: initializer) else { return nil }
    typealias Initializer = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject
    let initFunction = unsafeBitCast(allocated.method(for: initializer), to: Initializer.self)
    let operation = initFunction(allocated, initializer, [NSNumber(value: window)] as NSArray, target)
    guard operation.responds(to: perform) else { return nil }
    typealias Perform = @convention(c) (AnyObject, Selector) -> Void
    unsafeBitCast(operation.method(for: perform), to: Perform.self)(operation, perform)
    return operation
}
func spaces(_ window: UInt32) -> [UInt64] {
    let array = copySpaces(connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue()
    return (array as? [NSNumber] ?? []).map(\.uint64Value)
}
func writeJSON(_ object: Any, to path: String? = nil) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    if let path { try! data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    else { print(String(data: data, encoding: .utf8)!) }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let topology = copyManaged(connection)?.takeRetainedValue() as? [[String: Any]] ?? []
if CommandLine.arguments.contains("--fixture") {
    let window = NSWindow(contentRect: NSRect(x: 140, y: 180, width: 500, height: 320), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Electro Magnet disposable Spaces test"
    window.isReleasedWhenClosed = false
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        writeJSON(["pid": ProcessInfo.processInfo.processIdentifier, "windowID": window.windowNumber, "spaces": spaces(UInt32(window.windowNumber))], to: CommandLine.arguments.last!)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { window.close(); app.terminate(nil) }
    app.run()
} else if CommandLine.arguments.contains("--exercise") {
    let input = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments.last!))
    let fixture = try! JSONSerialization.jsonObject(with: input) as! [String: Any]
    var window = (fixture["windowID"] as! NSNumber).uint32Value
    let original = spaces(window)
    let targets = topology.flatMap { display -> [UInt64] in
        (display["Spaces"] as? [[String: Any]] ?? []).filter { ($0["type"] as? NSNumber)?.intValue == 0 }.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
    }
    var steps: [[String: Any]] = []
    for target in targets where !original.contains(target) {
        let prepare = setCompat(connection, target, 0x79616265)
        let move = setWorkspace(connection, &window, 1, 0x79616265)
        let cleanup = setCompat(connection, target, 0)
        Thread.sleep(forTimeInterval: 0.3)
        let compatObserved = spaces(window)
        if compatObserved != [target] {
            moveManaged(connection, [NSNumber(value: window)] as CFArray, target)
            Thread.sleep(forTimeInterval: 0.3)
        }
        let directObserved = spaces(window)
        let operation = moveBridged(window, target)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        withExtendedLifetime(operation) {}
        steps.append(["target": target, "prepare": prepare, "move": move, "cleanup": cleanup, "compatObserved": compatObserved, "directObserved": directObserved, "bridgedAvailable": operation != nil, "observed": spaces(window), "passed": spaces(window) == [target]])
    }
    if let target = original.first {
        let operation = moveBridged(window, target)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        withExtendedLifetime(operation) {}
        moveManaged(connection, [NSNumber(value: window)] as CFArray, target)
        _ = setCompat(connection, target, 0x79616265)
        _ = setWorkspace(connection, &window, 1, 0x79616265)
        _ = setCompat(connection, target, 0)
    }
    Thread.sleep(forTimeInterval: 0.3)
    writeJSON(["original": original, "steps": steps, "restored": spaces(window), "passed": !steps.isEmpty && steps.allSatisfy { $0["passed"] as? Bool == true } && spaces(window) == original])
} else {
    writeJSON(["connection": connection, "screensHaveSeparateSpaces": NSScreen.screensHaveSeparateSpaces, "topology": topology])
}
