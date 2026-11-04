import SwitchCore
import Testing

@Suite struct SwitchSessionTests {
    @Test func swipingRightStartsOnTheSecondItem() {
        let session = SwitchSession(itemCount: 5, direction: .right, began: 0)

        #expect(session.selection == 1)
    }

    @Test func swipingLeftStartsOnTheLastItem() {
        let session = SwitchSession(itemCount: 5, direction: .left, began: 0)

        #expect(session.selection == 4)
    }

    @Test func aSingleItemStaysSelected() {
        var session = SwitchSession(itemCount: 1, direction: .right, began: 0)
        session.move(travel: 50)

        #expect(session.selection == 0)
        #expect(session.outcome(endedAt: 1) == .cancel)
    }

    @Test func anEmptySwitcherCancels() {
        var session = SwitchSession(itemCount: 0, direction: .left, began: 0)
        session.move(travel: -50)

        #expect(session.outcome(endedAt: 1) == .cancel)
    }

    @Test func eachStepMovesTheSelectionByOneItem() {
        var session = SwitchSession(itemCount: 10, direction: .right, began: 0)

        #expect(session.move(travel: 6) == false)
        #expect(session.move(travel: 7) == true)
        #expect(session.selection == 2)
        session.move(travel: 17)
        #expect(session.selection == 3)
        session.move(travel: 37)
        #expect(session.selection == 5)
    }

    @Test func movingBackMovesTheSelectionBack() {
        var session = SwitchSession(itemCount: 10, direction: .right, began: 0)
        session.move(travel: 27)
        #expect(session.selection == 4)

        session.move(travel: 23)
        #expect(session.selection == 3)
        session.move(travel: -7)
        #expect(session.selection == 0)
    }

    @Test func fingersRestingOnABoundaryDoNotFlipTheSelection() {
        var session = SwitchSession(itemCount: 10, direction: .right, began: 0)
        session.move(travel: 6.6)
        #expect(session.selection == 2)

        for travel in [5.1, 6.4, 4.9, 6.2, 3.6] {
            #expect(session.move(travel: travel) == false)
        }
        #expect(session.selection == 2)
    }

    @Test func theSelectionStopsAtTheEndsWithoutWrapping() {
        var session = SwitchSession(itemCount: 4, direction: .right, began: 0)
        session.move(travel: 120)
        #expect(session.selection == 3)

        var leftward = SwitchSession(itemCount: 4, direction: .left, began: 0)
        leftward.move(travel: -120)
        #expect(leftward.selection == 0)
        leftward.move(travel: 120)
        #expect(leftward.selection == 3)
    }

    @Test func turningBackAfterPushingPastTheEndRespondsRightAway() {
        var session = SwitchSession(itemCount: 4, direction: .right, began: 0)
        session.move(travel: 120)

        session.move(travel: 113)
        #expect(session.selection == 2)
    }

    @Test func liftingWithTheCurrentItemSelectedCancels() {
        var session = SwitchSession(itemCount: 5, direction: .right, began: 0)
        session.move(travel: -8)
        #expect(session.selection == 0)

        #expect(session.outcome(endedAt: 1) == .cancel)
    }

    @Test func liftingAfterTheSwitcherAppearsActivatesTheSelection() {
        var session = SwitchSession(itemCount: 5, direction: .right, began: 10)
        session.move(travel: 17)

        #expect(session.outcome(endedAt: 10.5) == .activate(item: 3))
    }

    @Test(arguments: [(Direction.right, 40.0), (.right, -8), (.left, -25), (.left, 0)])
    func aQuickSwitchActivatesTheSecondItem(direction: Direction, travel: Double) {
        var session = SwitchSession(itemCount: 5, direction: direction, began: 10)
        session.move(travel: travel)

        #expect(session.outcome(endedAt: 10.15) == .activate(item: 1))
    }

    @Test func choosingStartsOnTheFirstItemAndActivatesIt() {
        let session = SwitchSession(choosingAmong: 3)

        #expect(session.selection == 0)
        #expect(session.outcome(endedAt: 0) == .activate(item: 0))
    }

    @Test func choosingMovesAndActivatesTheSelection() {
        var session = SwitchSession(choosingAmong: 3)
        session.move(travel: 7)
        #expect(session.selection == 1)
        session.move(travel: -20)
        #expect(session.selection == 0)
        session.move(travel: 30)

        #expect(session.outcome(endedAt: 0) == .activate(item: 2))
    }

    @Test func choosingAmongNothingCancels() {
        #expect(SwitchSession(choosingAmong: 0).outcome(endedAt: 0) == .cancel)
    }

    @Test func startingOnTheCurrentItemCancelsThere() {
        var session = SwitchSession(onCurrentItemOf: 4)
        #expect(session.selection == 0)
        #expect(session.outcome(endedAt: 0) == .cancel)

        session.move(travel: 7)
        #expect(session.outcome(endedAt: 0) == .activate(item: 1))
    }
}
