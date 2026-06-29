import AppKit
import IMKSwift

let bundle = Bundle.main
let bundleIdentifier = bundle.bundleIdentifier ?? "org.uonr.inputmethod.Xnheime"
let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
let serverName = connectionName?.isEmpty == false ? connectionName! : "\(bundleIdentifier)_Connection"

let server = IMKServer(name: serverName, bundleIdentifier: bundleIdentifier)
_ = server

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
