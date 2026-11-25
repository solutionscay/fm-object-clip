import AppKit
@testable import FMClipCore

extension ClipboardWatcher {
    /// Two checks, as the timer makes them: the first sees the change, the second reads the same contents and
    /// captures them. Returns the captured objects.
    @discardableResult
    func settle() -> [FMObject] {
        poll()
        return poll()
    }
}
