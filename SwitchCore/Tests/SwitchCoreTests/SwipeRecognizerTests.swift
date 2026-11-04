import Foundation
import SwitchCore
import Testing

@Suite struct SwipeRecognizerTests {
    @Test func threeFingersMovingSidewaysOpenASession() {
        var trackpad = Trackpad()
        trackpad.land(3)

        #expect(trackpad.move(dx: 2) == [])
        #expect(trackpad.move(dx: 1.5) == [.began(fingers: 3, direction: .right, time: trackpad.time)])
    }

    @Test func landingFingersArmTheRecognizer() {
        var trackpad = Trackpad()

        #expect(trackpad.land(2) == [])
        #expect(trackpad.land(1) == [.armed(fingers: 3)])
        #expect(trackpad.land(1) == [.armed(fingers: 4)])
        #expect(trackpad.land(1) == [])
    }

    @Test func fourFingersOpenASessionToTheLeft() {
        var trackpad = Trackpad()
        trackpad.land(4)

        #expect(trackpad.move(dx: -7) == [.began(fingers: 4, direction: .left, time: trackpad.time)])
    }

    @Test(arguments: [1, 2, 5])
    func otherFingerCountsDoNothing(fingers: Int) {
        var trackpad = Trackpad()
        trackpad.land(fingers)

        #expect(trackpad.move(dx: 30) == [])
    }

    @Test func aVerticalSwipeIsIgnoredUntilTheFingersLift() {
        var trackpad = Trackpad()
        trackpad.land(3)
        #expect(trackpad.move(dx: 1, dy: 4) == [])
        #expect(trackpad.move(dx: 30) == [])

        trackpad.liftAll()
        trackpad.land(3)
        #expect(trackpad.move(dx: 8) == [.began(fingers: 3, direction: .right, time: trackpad.time)])
    }

    @Test func threeFingersMovingDownOpenASession() {
        var trackpad = Trackpad()
        trackpad.land(3)

        #expect(trackpad.move(dx: 1, dy: -2) == [])
        #expect(trackpad.move(dx: 0, dy: -1.5) == [.beganDown(fingers: 3, time: trackpad.time)])
        #expect(trackpad.move(dx: 8).count == 1)
        #expect(trackpad.lift(1) == [.ended(time: trackpad.time)])
    }

    @Test func aMostlyDownwardDiagonalSwipeDoesNotOpen() {
        var trackpad = Trackpad()
        trackpad.land(3)

        #expect(trackpad.move(dx: 2.5, dy: -4) == [])
        #expect(trackpad.move(dx: 0, dy: -10) == [])
    }

    @Test func aDiagonalSwipeDoesNotOpen() {
        var trackpad = Trackpad()
        trackpad.land(3)

        #expect(trackpad.move(dx: 4, dy: 3) == [])
    }

    @Test func travelCountsFromTheOpeningPoint() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)

        let events = trackpad.move(dx: 12)

        #expect(events.count == 1)
        guard case .moved(let travel) = events.first else { Issue.record("expected .moved"); return }
        #expect(abs(travel - 12) < 0.001)
    }

    @Test func landingFingersOneByOneRestartsTheTravel() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 2)
        trackpad.land(1)

        #expect(trackpad.move(dx: 2) == [])
        #expect(trackpad.move(dx: 1.5) == [.began(fingers: 4, direction: .right, time: trackpad.time)])
    }

    @Test func aFingerLandingMidSessionDoesNotMoveIt() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)
        trackpad.land(1, at: 0.9)

        #expect(trackpad.move(dx: 0) == [])
    }

    @Test func liftingOneFingerEndsTheSessionAndNothingFollows() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)

        #expect(trackpad.lift(1) == [.ended(time: trackpad.time)])
        #expect(trackpad.move(dx: 20) == [])
        #expect(trackpad.lift(2) == [])
    }

    @Test func movingDownDuringASessionSwipesDownOnce() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)

        #expect(trackpad.move(dx: 0, dy: -4) == [])
        #expect(trackpad.move(dx: 0, dy: -3) == [.swiped(.down)])
        #expect(trackpad.move(dx: 0, dy: -3) == [])
        #expect(trackpad.move(dx: 0, dy: 10) == [.swiped(.up)])
    }

    @Test func sidewaysWobbleDuringAStrokeStillCountsAsTravel() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)

        let events = trackpad.move(dx: 1, dy: -4)
        #expect(events.count == 1)
        guard case .moved(let travel) = events.first else { Issue.record("expected .moved"); return }
        #expect(abs(travel - 1) < 0.001)
        #expect(trackpad.move(dx: 1, dy: -3) == [.swiped(.down)])
    }

    @Test func driftWhileSteppingSidewaysDoesNotSwipe() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)

        for _ in 0..<10 {
            let events = trackpad.move(dx: 4, dy: -1.5)
            #expect(!events.contains(.swiped(.down)))
        }
    }

    @Test func aDiagonalMoveDuringASessionDoesNotSwipe() {
        var trackpad = Trackpad()
        trackpad.land(3)
        trackpad.move(dx: 7)

        #expect(!trackpad.move(dx: 6, dy: -8).contains(.swiped(.down)))
    }

    @Test func recordedSwipesSplitIntoDeliberateSwipesAndQuickSwitches() throws {
        let url = try #require(Bundle.module.url(forResource: "three-finger-swipes", withExtension: "jsonl",
                                                 subdirectory: "Fixtures"))
        let frames = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONDecoder().decode(TouchFrame.self, from: Data($0.utf8)) }

        var recognizer = SwipeRecognizer()
        var sessions: [(direction: Direction, began: Double, travel: Double, ended: Double)] = []
        var strokes = 0
        for event in frames.compactMap({ recognizer.handle($0) }) {
            switch event {
            case .began(let fingers, let direction, let time):
                #expect(fingers == 3)
                sessions.append((direction, time, 0, .nan))
            case .moved(let travel):
                sessions[sessions.count - 1].travel = travel
            case .ended(let time):
                sessions[sessions.count - 1].ended = time
            case .swiped, .beganDown:
                strokes += 1
            case .armed:
                break
            }
        }

        let deliberate = sessions.filter { $0.ended - $0.began >= SwitchSession.Settings().quickSwitchDuration }
        let quick = sessions.filter { $0.ended - $0.began < SwitchSession.Settings().quickSwitchDuration }
        #expect(sessions.count == 11)
        #expect(deliberate.map(\.direction) == [.left, .right, .left, .right])
        #expect(deliberate.allSatisfy { abs($0.travel) > 60 })
        #expect(quick.count == 7)
        #expect(quick.allSatisfy { abs($0.travel) < 45 })
        // Sideways swipes never stroke up or down.
        #expect(strokes == 0)
    }
}

/// Builds touch frames for fingers lined up across a 160×100 mm trackpad.
private struct Trackpad {
    private(set) var time = 0.0
    private var fingers: [Touch] = []
    private var recognizer = SwipeRecognizer()
    private var nextID = 1
    private let surface = Size(width: 160, height: 100)

    @discardableResult
    mutating func land(_ count: Int, at x: Double? = nil) -> [SwipeEvent] {
        for _ in 0..<count {
            let position = x ?? 0.3 + 0.05 * Double(fingers.count)
            fingers.append(Touch(id: nextID, x: position, y: 0.5, phase: .began))
            nextID += 1
        }
        return send()
    }

    /// Moves every finger by the given distance in millimetres, in one frame.
    @discardableResult
    mutating func move(dx: Double, dy: Double = 0) -> [SwipeEvent] {
        for index in fingers.indices {
            fingers[index].x += dx / surface.width
            fingers[index].y += dy / surface.height
            fingers[index].phase = .moved
        }
        return send()
    }

    @discardableResult
    mutating func lift(_ count: Int) -> [SwipeEvent] {
        for index in fingers.indices.suffix(count) { fingers[index].phase = .ended }
        defer { fingers.removeAll { $0.phase == .ended } }
        return send()
    }

    mutating func liftAll() {
        lift(fingers.count)
    }

    private mutating func send() -> [SwipeEvent] {
        time += 0.008
        let events = recognizer.handle(TouchFrame(time: time, surface: surface, touches: fingers))
        for index in fingers.indices where fingers[index].phase == .began { fingers[index].phase = .stationary }
        return events.map { [$0] } ?? []
    }
}
