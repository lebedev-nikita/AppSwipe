/// Horizontal direction of finger travel.
public enum Direction: Sendable {
    case left, right
}

/// Vertical direction of finger travel.
public enum VerticalDirection: Sendable {
    case up, down
}

/// What `SwipeRecognizer` reports about the swipe that drives a Switch Session.
public enum SwipeEvent: Equatable, Sendable {
    /// A number of fingers that can open a Switcher has landed, so a session may follow. Reported
    /// again whenever the set of fingers changes before a session opens.
    case armed(fingers: Int)
    /// Enough fingers travelled far enough sideways to open a Switcher.
    case began(fingers: Int, direction: Direction, time: Double)
    /// Enough fingers travelled far enough down to open a Switcher. Moving up never opens one.
    case beganDown(fingers: Int, time: Double)
    /// Horizontal travel since `began`, in millimetres. Positive is to the right.
    case moved(travel: Double)
    /// During a session, the fingers moved up or down far enough, and more up or down than sideways.
    /// Reported once per stroke; sideways travel during it still counts towards `moved`.
    case swiped(VerticalDirection)
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
        /// Vertical travel during a session that makes a stroke up or down, in millimetres.
        public var strokeTravel = 6.0
        /// Whether a palm on the trackpad is left out of the finger count. Otherwise every touch counts.
        public var ignoresPalms = true
        /// How far a touch must travel, as a share of the farthest one, to count as a swiping finger
        /// when palms are ignored. A palm beside the fingers barely moves, so it falls short.
        public var swipingShare = 1.0 / 3

        public init() {}
    }

    private enum State {
        /// Fewer fingers than any Switcher needs.
        case idle
        /// Enough touches for a Switcher are down. `travel` holds each one's travel from the moment
        /// this exact set landed.
        case tracking(touches: Set<Int>, travel: [Int: Vector])
        /// The swipe isn't a Switch Session, or its session is over; ignore it until `fingers` lift.
        /// Other touches, such as a palm, may stay down.
        case ignoring(fingers: Set<Int>)
        /// A Switch Session is open. `stroke` counts from the moment the fingers last moved sideways.
        case swiping(fingers: Set<Int>, travel: Double, stroke: Vector)
    }

    private struct Vector {
        var x = 0.0
        var y = 0.0

        var length: Double { (x * x + y * y).squareRoot() }
    }

    /// Changes apply from the next frame.
    public var settings: Settings
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
            // macOS recognizes a resting palm or thumb, which never helps open a Switcher.
            let touches = Set(down.values.filter { !settings.ignoresPalms || !$0.isResting }.map(\.id))
            guard touches.count >= settings.fingerCounts.min() ?? 0 else {
                state = .idle
                return nil
            }
            guard case .tracking(let tracked, var travel) = state, tracked == touches else {
                state = .tracking(touches: touches, travel: [:])
                return settings.fingerCounts.contains(touches.count) ? .armed(fingers: touches.count) : nil
            }
            for id in touches {
                let delta = movement(of: [id], to: down, surface: frame.surface)
                travel[id, default: Vector()].x += delta.x
                travel[id, default: Vector()].y += delta.y
            }
            // Only the touches that keep up with the farthest one are swiping fingers.
            let farthest = travel.values.map(\.length).max() ?? 0
            let share = settings.ignoresPalms ? settings.swipingShare : 0
            let fingers = touches.filter { (travel[$0]?.length ?? 0) >= share * farthest }
            var mean = Vector()
            for id in fingers {
                mean.x += travel[id]?.x ?? 0
                mean.y += travel[id]?.y ?? 0
            }
            mean.x /= Double(fingers.count)
            mean.y /= Double(fingers.count)
            let opensSideways = abs(mean.x) >= settings.openingTravel
                && abs(mean.x) >= settings.horizontalBias * abs(mean.y)
            let opensVertically = abs(mean.y) >= settings.openingTravel && abs(mean.y) > abs(mean.x)
            guard opensSideways || opensVertically else {
                state = .tracking(touches: touches, travel: travel)
                return nil
            }
            guard settings.fingerCounts.contains(fingers.count),
                  opensSideways || (mean.y < 0 && abs(mean.y) >= settings.horizontalBias * abs(mean.x))
            else {
                state = .ignoring(fingers: fingers)
                return nil
            }
            state = .swiping(fingers: fingers, travel: 0, stroke: Vector())
            return opensSideways
                ? .began(fingers: fingers.count, direction: mean.x > 0 ? .right : .left, time: frame.time)
                : .beganDown(fingers: fingers.count, time: frame.time)

        case .ignoring(let fingers):
            if fingers.isDisjoint(with: ids) { state = .idle }
            return nil

        case .swiping(let fingers, var travel, var stroke):
            guard fingers.isSubset(of: ids) else {
                let lingering = fingers.intersection(ids)
                state = lingering.isEmpty ? .idle : .ignoring(fingers: lingering)
                return .ended(time: frame.time)
            }
            // Only the fingers that opened the session count, so a finger landing later doesn't move it.
            let delta = movement(of: fingers, to: down, surface: frame.surface)
            guard delta.x != 0 || delta.y != 0 else { return nil }
            travel += delta.x
            stroke.x += delta.x
            stroke.y += delta.y
            defer { state = .swiping(fingers: fingers, travel: travel, stroke: stroke) }
            if abs(stroke.y) >= settings.strokeTravel, abs(stroke.y) >= settings.horizontalBias * abs(stroke.x) {
                let direction: VerticalDirection = stroke.y > 0 ? .up : .down
                stroke = Vector()
                return .swiped(direction)
            }
            // Moving sideways starts the next stroke afresh, so drift while stepping through Items adds
            // up to none.
            if abs(stroke.x) >= settings.openingTravel, abs(stroke.x) >= abs(stroke.y) { stroke = Vector() }
            return delta.x != 0 ? .moved(travel: travel) : nil
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
