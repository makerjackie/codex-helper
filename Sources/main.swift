import AppKit
import Darwin

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
