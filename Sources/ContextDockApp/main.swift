import AppKit

// Background (accessory) app: no Dock icon, panel-only UI.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
