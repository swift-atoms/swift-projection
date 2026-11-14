extension Projection {
    /// The rectangle of an image that normalised device coordinates map onto: x from −1 to 1 across
    /// its width, and y from −1 to 1 along its height in the `direction` the image's y grows.
    @frozen
    public struct Viewport {
        /// The x of the rectangle's left edge, where a normalised x of −1 lands.
        public let x: Scalar
        /// The least y of the rectangle: its top edge in an image whose y grows downward, its bottom
        /// edge in one whose y grows upward.
        public let y: Scalar
        public let width: Scalar
        public let height: Scalar
        /// Which way the image's y grows, and so which edge a normalised y of 1 lands on.
        public let direction: Direction

        @inlinable
        public init(x: Scalar, y: Scalar, width: Scalar, height: Scalar, direction: Direction) throws(Error) {
            guard x.isFinite, y.isFinite, width.isFinite, height.isFinite else { throw .nonfinite }
            guard width > 0, height > 0 else { throw .empty }
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.direction = direction
        }
    }
}

extension Projection.Viewport: Equatable {}
extension Projection.Viewport: Hashable where Scalar: Hashable {}
extension Projection.Viewport: Sendable where Scalar: Sendable {}

extension Projection.Viewport {

    /// The point of the image at normalised coordinates: `x + (n.x + 1) / 2 · width` across, and along
    /// the height `y + (1 − n.y) / 2 · height` when y grows downward or `y + (n.y + 1) / 2 · height`
    /// when it grows upward. It is affine, and points outside −1…1 land outside the rectangle.
    @inlinable
    public func point(_ normalized: Point<2, Scalar>) -> Point<2, Scalar> {
        let across = x + (normalized.x + 1) / 2 * width
        switch direction {
        case .down: return Point(x: across, y: y + (1 - normalized.y) / 2 * height)
        case .up: return Point(x: across, y: y + (normalized.y + 1) / 2 * height)
        }
    }

    /// The normalised coordinates of a point of the image: the inverse of `point(_:)`, so
    /// `normalized(point(n))` is `n` up to rounding.
    @inlinable
    public func normalized(_ point: Point<2, Scalar>) -> Point<2, Scalar> {
        let across = 2 * (point.x - x) / width - 1
        switch direction {
        case .down: return Point(x: across, y: 1 - 2 * (point.y - y) / height)
        case .up: return Point(x: across, y: 2 * (point.y - y) / height - 1)
        }
    }
}

#if !hasFeature(Embedded)
    extension Projection.Viewport {
        private enum CodingKeys: String, CodingKey {
            case x, y, width, height, direction
        }
    }

    extension Projection.Viewport: Encodable where Scalar: Encodable {
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encode(direction, forKey: .direction)
        }
    }

    extension Projection.Viewport: Decodable where Scalar: Decodable {
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            do {
                try self.init(
                    x: try container.decode(Scalar.self, forKey: .x),
                    y: try container.decode(Scalar.self, forKey: .y),
                    width: try container.decode(Scalar.self, forKey: .width),
                    height: try container.decode(Scalar.self, forKey: .height),
                    direction: try container.decode(Direction.self, forKey: .direction)
                )
            } catch let error as Projection.Error {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "A viewport requires a finite rectangle with positive width and height: \(error)"
                    )
                )
            }
        }
    }
#endif
