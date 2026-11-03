/// Which Switcher a swipe opens.
public enum SwitcherKind: Sendable {
    case apps, windows

    public init?(fingers: Int) {
        switch fingers {
        case 3: self = .apps
        case 4: self = .windows
        default: return nil
        }
    }
}

/// The Selection of one Switch Session, moved by finger travel.
public struct SwitchSession: Sendable {
    public struct Settings: Sendable {
        /// Finger travel that moves the Selection by one Item, in millimetres.
        public var stepLength = 10.0
        /// Lifting the fingers within this many seconds of the session's start is a Quick Switch.
        public var quickSwitchDuration = 0.2
        /// Extra travel, as a fraction of a Step, past the midpoint between Items before the Selection
        /// moves. It keeps a resting finger from flipping the Selection back and forth.
        public var hysteresis = 0.15

        public init() {}
    }

    public enum Outcome: Equatable, Sendable {
        case activate(item: Int)
        case cancel
    }

    public let itemCount: Int
    public private(set) var selection: Int

    private let settings: Settings
    private let began: Double
    /// The travel at which the finger position maps onto `start`.
    private var origin = 0.0
    private let start: Int

    /// - Parameters:
    ///   - itemCount: Items in the Switcher, the Current Item first.
    ///   - direction: Where the fingers first moved. Right selects the second Item, left the last.
    ///   - began: When the session started, in the touch frames' clock.
    public init(itemCount: Int, direction: Direction, began: Double, settings: Settings = .init()) {
        self.itemCount = itemCount
        self.began = began
        self.settings = settings
        start = switch (itemCount, direction) {
        case (...1, _): 0
        case (_, .right): 1
        case (_, .left): itemCount - 1
        }
        selection = start
    }

    /// Moves the Selection for the total travel since the session began. Returns whether it changed.
    @discardableResult
    public mutating func move(travel: Double) -> Bool {
        let before = selection
        let last = max(itemCount - 1, 0)
        let threshold = 0.5 + settings.hysteresis
        // Where the fingers are, measured in Items.
        var position = Double(start) + (travel - origin) / settings.stepLength
        while position >= Double(selection) + threshold, selection < last { selection += 1 }
        while position <= Double(selection) - threshold, selection > 0 { selection -= 1 }
        // At either end, drop the travel past the end Item, so turning back responds right away.
        if (selection == last && position > Double(last)) || (selection == 0 && position < 0) {
            position = Double(selection)
            origin = travel - (position - Double(start)) * settings.stepLength
        }
        return selection != before
    }

    /// The result of lifting the fingers at `time`.
    public func outcome(endedAt time: Double) -> Outcome {
        let isQuickSwitch = time - began < settings.quickSwitchDuration
        let item = isQuickSwitch ? 1 : selection
        guard itemCount > 1, item > 0 else { return .cancel }
        return .activate(item: item)
    }
}
