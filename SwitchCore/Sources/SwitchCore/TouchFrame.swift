/// A snapshot of every finger on one trackpad at one moment.
public struct TouchFrame: Codable, Equatable, Sendable {
    /// Seconds since system startup.
    public var time: Double
    /// Size of the trackpad surface, in millimetres.
    public var surface: Size
    public var touches: [Touch]

    public init(time: Double, surface: Size, touches: [Touch]) {
        self.time = time
        self.surface = surface
        self.touches = touches
    }

    /// Touches still in contact with the surface.
    public var fingersDown: [Touch] {
        touches.filter(\.isDown)
    }
}

public struct Touch: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case began, moved, stationary, ended, cancelled
    }

    /// Stays the same for as long as one finger keeps contact.
    public var id: Int
    /// Position from the left edge of the surface, 0 to 1.
    public var x: Double
    /// Position from the bottom edge of the surface, 0 to 1.
    public var y: Double
    public var phase: Phase
    /// Whether macOS takes the touch for a resting palm or thumb rather than a finger.
    public var isResting: Bool

    public init(id: Int, x: Double, y: Double, phase: Phase, isResting: Bool = false) {
        self.id = id
        self.x = x
        self.y = y
        self.phase = phase
        self.isResting = isResting
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, phase
        case isResting = "resting"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        phase = try container.decode(Phase.self, forKey: .phase)
        // Recordings made before the field existed have none.
        isResting = try container.decodeIfPresent(Bool.self, forKey: .isResting) ?? false
    }

    public var isDown: Bool {
        switch phase {
        case .began, .moved, .stationary: true
        case .ended, .cancelled: false
        }
    }
}

public struct Size: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
