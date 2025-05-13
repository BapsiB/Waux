import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    
    // Set a specific window size
    let windowSize = NSSize(width: 1200, height: 800)
    let screenFrame = NSScreen.main?.frame ?? .zero
    let windowOrigin = NSPoint(
      x: (screenFrame.width - windowSize.width) / 2,
      y: (screenFrame.height - windowSize.height) / 2
    )
    let newFrame = NSRect(origin: windowOrigin, size: windowSize)
    self.setFrame(newFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
