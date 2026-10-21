// Prints the macOS activation policy of a process: regular (Dock icon), accessory, prohibited, or none.
// usage: swift app-policy.swift PID
import AppKit

guard let arg = CommandLine.arguments.dropFirst().first, let pid = pid_t(arg),
      let app = NSRunningApplication(processIdentifier: pid) else { print("none"); exit(0) }
switch app.activationPolicy {
case .regular: print("regular")
case .accessory: print("accessory")
case .prohibited: print("prohibited")
@unknown default: print("unknown")
}
