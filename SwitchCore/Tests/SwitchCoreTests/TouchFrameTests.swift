import Foundation
import SwitchCore
import Testing

@Suite struct TouchFrameTests {
    @Test func liftedFingersAreNotDown() {
        let frame = TouchFrame(
            time: 0,
            surface: Size(width: 160, height: 100),
            touches: [
                Touch(id: 1, x: 0.4, y: 0.5, phase: .moved),
                Touch(id: 2, x: 0.5, y: 0.5, phase: .stationary),
                Touch(id: 3, x: 0.6, y: 0.5, phase: .ended),
                Touch(id: 4, x: 0.7, y: 0.5, phase: .cancelled),
            ])

        #expect(frame.fingersDown.map(\.id) == [1, 2])
    }

    @Test func decodesARecordedLine() throws {
        let line = #"{"time":12.5,"surface":{"width":160,"height":100},"touches":[{"id":1,"x":0.25,"y":0.75,"phase":"began"}]}"#

        let frame = try JSONDecoder().decode(TouchFrame.self, from: Data(line.utf8))

        #expect(frame == TouchFrame(
            time: 12.5,
            surface: Size(width: 160, height: 100),
            touches: [Touch(id: 1, x: 0.25, y: 0.75, phase: .began)]))
    }
}
