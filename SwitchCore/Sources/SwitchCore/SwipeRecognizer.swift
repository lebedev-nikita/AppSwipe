/// Horizontal direction of finger travel.
public enum Direction: Sendable {
    case left, right
}

/// What `SwipeRecognizer` reports about the swipe that drives a Switch Session.
public enum SwipeEvent: Equatable, Sendable {
    /// A number of fingers that can open a Switcher has landed, so a session may follow. Reported
    /// again whenever the set of fingers changes before a session opens.
    case armed(fingers: Int)
    /// Enough fingers travelled far enough sideways to open a Switcher.
    case began(fingers: Int, direction: Direction, time: Double)
    /// Horizontal travel since `began`, in millimetres. Positive is to the right.
    case moved(travel: Double)
    /// One of the swiping fingers lifted, which ends the Switch Session.
    case ended(time: Double)
}

/// Recognizes Switch Session swipes in a stream of touch frames from one trackpad.
public struct SwipeRecognizer: Sendable {
    public struct Settings: Sendable {
        /// Finger counts that can open a Switcher.
        public var fingerCounts: Set<Int> = [3, 4]
        /// Sideways travel that opens a Switcher, in millimetres.
        public var openingTravel = 3.0
        /// How many times farther the fingers must travel sideways than vertically.
        public var horizontalBias = 2.0

        public init() {}
    }

    private enum State {
        /// Fewer fingers than any Switcher needs.
        case idle
        /// A usable number of fingers is down; `travel` counts from the moment this exact set landed.
        case tracking(fingers: Set<Int>, travel: Vector)
        /// The touch isn't a Switch Session; ignore it until every finger lifts.
        case ignoring
        /// A Switch Session is open.
        case swiping(fingers: Set<Int>, travel: Double)
    }

    private struct Vector {
        var x = 0.0
        var y = 0.0
    }

    private let settings: Settings
    private var state = State.idle
    private var previous: [Int: Touch] = [:]

    public init(settings: Settings = .init()) {
        self.settings = settings
    }

    public mutating func handle(_ frame: TouchFrame) -> SwipeEvent? {
        let down = Dictionary(uniqueKeysWithValues: frame.fingersDown.map { ($0.id, $0) })
        defer { previous = down }
        let ids = Set(down.keys)

        switch state {
        case .idle, .tracking:
            guard settings.fingerCounts.contains(ids.count) else {
                state = ids.count > settings.fingerCounts.max() ?? 0 ? .ignoring : .idle
                return nil
            }
            guard case .tracking(let fingers, var travel) = state, fingers == ids else {
                state = .tracking(fingers: ids, travel: Vector())
                return .armed(fingers: ids.count)
            }
            let delta = movement(of: ids, to: down, surface: frame.surface)
            travel.x += delta.x
            travel.y += delta.y
            if abs(travel.x) >= settings.openingTravel, abs(travel.x) >= settings.horizontalBias * abs(travel.y) {
                state = .swiping(fingers: ids, travel: 0)
                return .began(fingers: ids.count, direction: travel.x > 0 ? .right : .left, time: frame.time)
            }
            if abs(travel.y) >= settings.openingTravel, abs(travel.y) > abs(travel.x) {
                state = .ignoring
                return nil
            }
            state = .tracking(fingers: ids, travel: travel)
            return nil

        case .ignoring:
            if ids.isEmpty { state = .idle }
            return nil

        case .swiping(let fingers, var travel):
            guard fingers.isSubset(of: ids) else {
                state = ids.isEmpty ? .idle : .ignoring
                return .ended(time: frame.time)
            }
            // Only the fingers that opened the session count, so a finger landing later doesn't move it.
            let delta = movement(of: fingers, to: down, surface: frame.surface).x
            guard delta != 0 else { return nil }
            travel += delta
            state = .swiping(fingers: fingers, travel: travel)
            return .moved(travel: travel)
        }
    }

    /// Average movement of `fingers` since the previous frame, in millimetres.
    private func movement(of fingers: Set<Int>, to down: [Int: Touch], surface: Size) -> Vector {
        var sum = Vector()
        for id in fingers {
            guard let now = down[id], let before = previous[id] else { return Vector() }
            sum.x += now.x - before.x
            sum.y += now.y - before.y
        }
        let count = Double(fingers.count)
        return Vector(x: sum.x / count * surface.width, y: sum.y / count * surface.height)
    }
}
