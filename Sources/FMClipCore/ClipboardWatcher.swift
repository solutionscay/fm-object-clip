import AppKit

/// Does a check of the pasteboard change count on a timer. macOS sends no event when the clipboard changes.
/// Calls `onCapture` with the FileMaker objects of each new clipboard contents. Contents with no FileMaker class
/// call `onOther` (for example, plain text).
///
/// The change count changes on `clearContents` and `declareTypes`, not on each `setData`. So a tool can still add data
/// after the check sees the change. For this reason the watcher does not capture at once. It reads the contents (the
/// FileMaker objects, `FOPN` and `FOPF`) at each check, and it captures one time per change count:
/// - when two checks in a row read the same contents, or
/// - when `maxWait` has gone by since the change, with the contents of that check.
/// After the capture, the watcher does not read that change count again. Data that comes later is ignored.
/// A new change count before the capture drops the contents that did not settle, and the wait starts again.
///
/// `onOther` does not wait: it runs at the first check of a change whose contents have no FileMaker class. Its job is
/// only to say "the clipboard has other contents now" (the app forgets the restore record), and that is already true
/// at the first check. So a plain-text copy that a newer change replaces before it settles still calls `onOther`.
/// `onOther` runs at most one time for each change. A change that has FileMaker objects never calls it.
public final class ClipboardWatcher {
    /// The maximum time from a change to its capture, in seconds.
    public static let maxWait: TimeInterval = 1.2
    public let pasteboard: NSPasteboard
    public let interval: TimeInterval
    private let onCapture: ([FMObject]) -> Void
    private let onOther: (() -> Void)?
    /// The change count of the last change that the watcher saw (captured, waiting or ignored).
    private var lastChangeCount: Int
    private var timer: Timer?

    /// The contents of a change that waits for its capture.
    private struct Pending {
        var contents: Contents
        let since: Date
        /// True when `onOther` ran for this change.
        var otherCalled: Bool
    }

    /// What the watcher compares between two checks.
    private struct Contents: Equatable {
        let objects: [FMObject]
        let name: String?
        let folder: String?
    }

    private var pending: Pending?
    /// The clock (tests can change it).
    var now: () -> Date = Date.init

    public init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.4,
                onOther: (() -> Void)? = nil, onCapture: @escaping ([FMObject]) -> Void) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.onCapture = onCapture
        self.onOther = onOther
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Starts the timer on the current run loop.
    public func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.current.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ignores the clipboard contents of this change count, for example a copy from the app itself.
    /// A change that still waits for its capture is dropped too: the clipboard has other contents now.
    public func ignore(changeCount: Int) {
        if changeCount > lastChangeCount {
            lastChangeCount = changeCount
            pending = nil
        }
    }

    /// Does one check now. Returns the captured objects: empty if nothing was captured at this check (no change, the
    /// contents do not have a FileMaker class, or the contents have not settled yet).
    @discardableResult
    public func poll() -> [FMObject] {
        let count = pasteboard.changeCount
        let contents = read()
        if count != lastChangeCount {
            lastChangeCount = count
            let other = contents.objects.isEmpty
            if other { onOther?() }
            pending = Pending(contents: contents, since: now(), otherCalled: other)
            return []
        }
        guard var p = pending else { return [] }
        guard contents == p.contents || now().timeIntervalSince(p.since) >= Self.maxWait else {
            p.contents = contents
            pending = p
            return []
        }
        pending = nil
        if !contents.objects.isEmpty {
            onCapture(contents.objects)
        } else if !p.otherCalled {
            onOther?()
        }
        return contents.objects
    }

    private func read() -> Contents {
        Contents(objects: FMPasteboard.read(pasteboard),
                 name: FMPasteboard.readName(pasteboard), folder: FMPasteboard.readFolder(pasteboard))
    }
}
