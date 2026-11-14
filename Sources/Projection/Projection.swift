public struct Projection<Scalar: BinaryFloatingPoint> {
    public let kind: Kind
    public let left: Scalar
    public let right: Scalar
    public let bottom: Scalar
    public let top: Scalar
    public let near: Scalar
    public let far: Scalar
    public let depth: Depth

    public init(
        _ kind: Kind,
        left: Scalar,
        right: Scalar,
        bottom: Scalar,
        top: Scalar,
        near: Scalar,
        far: Scalar,
        depth: Depth
    ) throws(Error) {
        guard left.isFinite, right.isFinite, bottom.isFinite, top.isFinite, near.isFinite, !far.isNaN,
            far.isFinite || (kind == .perspective && far > 0)
        else { throw .nonfinite }
        guard left < right, bottom < top, near < far else { throw .empty }
        guard kind == .orthographic || near > 0 else { throw .behindEye }
        self.kind = kind
        self.left = left
        self.right = right
        self.bottom = bottom
        self.top = top
        self.near = near
        self.far = far
        self.depth = depth
    }
}

extension Projection: Equatable {}
extension Projection: Hashable where Scalar: Hashable {}
extension Projection: Sendable where Scalar: Sendable {}

extension Projection {

    public var coefficients: InlineArray<4, InlineArray<4, Scalar>> {
        let width = right - left
        let height = top - bottom
        let range = far - near
        var rows = InlineArray<4, InlineArray<4, Scalar>>(repeating: InlineArray(repeating: 0))
        switch kind {
        case .perspective:
            rows[0][0] = 2 * near / width
            rows[0][2] = (right + left) / width
            rows[1][1] = 2 * near / height
            rows[1][2] = (top + bottom) / height
            rows[3][2] = -1
            switch (depth, far.isFinite) {
            case (.symmetric, true):
                rows[2][2] = -(far + near) / range
                rows[2][3] = -2 * far * near / range

            case (.symmetric, false):
                rows[2][2] = -1
                rows[2][3] = -2 * near

            case (.unit, true):
                rows[2][2] = -far / range
                rows[2][3] = -far * near / range

            case (.unit, false):
                rows[2][2] = -1
                rows[2][3] = -near
            }

        case .orthographic:
            rows[0][0] = 2 / width
            rows[0][3] = -(right + left) / width
            rows[1][1] = 2 / height
            rows[1][3] = -(top + bottom) / height
            rows[3][3] = 1
            switch depth {
            case .symmetric:
                rows[2][2] = -2 / range
                rows[2][3] = -(far + near) / range

            case .unit:
                rows[2][2] = -1 / range
                rows[2][3] = -near / range
            }
        }
        return rows
    }

    public func clip(_ point: Point<3, Scalar>) -> Vector<4, Scalar> {
        let rows = coefficients
        return Vector(
            InlineArray { row in
                var result: Scalar = .zero
                (0..<3).forEach { column in result += rows[row][column] * point[column] }
                result += rows[row][3]
                return result
            }
        )
    }

    public func normalized(_ point: Point<3, Scalar>) -> Point<3, Scalar>? {
        let clip = clip(point)
        guard clip[3] != 0 else { return nil }
        return Point(x: clip[0] / clip[3], y: clip[1] / clip[3], z: clip[2] / clip[3])
    }

    public func eye(_ normalized: Point<3, Scalar>) -> Point<3, Scalar>? {
        let rows = coefficients
        switch kind {
        case .perspective:
            let denominator = normalized.z + rows[2][2]
            guard denominator != 0 else { return nil }
            let z = -rows[2][3] / denominator
            let w = -z
            return Point(
                x: (normalized.x * w - rows[0][2] * z) / rows[0][0],
                y: (normalized.y * w - rows[1][2] * z) / rows[1][1],
                z: z
            )

        case .orthographic:
            return Point(
                x: (normalized.x - rows[0][3]) / rows[0][0],
                y: (normalized.y - rows[1][3]) / rows[1][1],
                z: (normalized.z - rows[2][3]) / rows[2][2]
            )
        }
    }
}

extension Projection {

    /// The eye-space point a `distance` ahead of the eye, at z = −`distance`, whose normalised x and y
    /// are the ones given: the inverse of `normalized(_:)` for a known distance, so that the x and y of
    /// `normalized(eye(n, distance: d))` are `n`, and `eye` of the x and y of `normalized(p)` at distance
    /// −`p.z` is `p`, up to rounding. In a perspective projection the point lies on the
    /// line through the eye and the window point, `distance · (n.x + c02, n.y + c12) / (c00, c11)` across
    /// for the coefficients c; a negative distance gives the mirrored point behind the eye that projects
    /// to the same coordinates, and a distance of zero the eye itself, which projects nowhere. In an
    /// orthographic projection x and y do not depend on the distance.
    public func eye(_ normalized: Point<2, Scalar>, distance: Scalar) -> Point<3, Scalar> {
        let rows = coefficients
        let z = -distance
        switch kind {
        case .perspective:
            return Point(
                x: (normalized.x * distance - rows[0][2] * z) / rows[0][0],
                y: (normalized.y * distance - rows[1][2] * z) / rows[1][1],
                z: z
            )

        case .orthographic:
            return Point(
                x: (normalized.x - rows[0][3]) / rows[0][0],
                y: (normalized.y - rows[1][3]) / rows[1][1],
                z: z
            )
        }
    }

    /// How large the projection draws a ball of a radius about an eye-space centre, in normalised units of
    /// y: half the width of its outline across the line from the view axis to the outline's centre.
    ///
    /// In a perspective projection the outline is the exact silhouette, where the cone of sight lines that
    /// graze the ball meets the picture plane: an ellipse drawn out along the line from the axis, whose half
    /// width across that line is `c11 · radius / √(z² − radius²)`, which equals `c11 · sin α / √(cos² θ −
    /// sin² α)` for a centre at distance d, θ off the axis, and sin α = radius / d. On the axis that is
    /// `c11 · tan α`, the radius of a circle. Off the axis it is not the half length along the line, which is
    /// longer, and it is not the small-angle `c11 · radius / −z`. It is nil when the ball reaches the plane
    /// of the eye or behind it, −z ≤ radius. In an orthographic projection it is `c11 · radius`. Either is nil
    /// for a radius that is negative or not finite. The unit is the vertical one: in normalised x the same
    /// length is `c00 / c11` times as long, so in a viewport the outline measures the same both ways only
    /// when the viewport's aspect equals the window's.
    public func radius(of radius: Scalar, at center: Point<3, Scalar>) -> Scalar? {
        guard radius >= 0, radius.isFinite else { return nil }
        let scale = coefficients[1][1]
        guard kind == .perspective else { return scale * radius }
        let ahead = -center.z
        guard ahead > radius else { return nil }
        let room = ((ahead - radius) * (ahead + radius)).squareRoot()
        guard room > 0 else { return nil }
        return scale * radius / room
    }

    /// `radius(of:at:)` in the units of a viewport: times half the viewport's height.
    public func radius(of radius: Scalar, at center: Point<3, Scalar>, in viewport: Viewport) -> Scalar? {
        self.radius(of: radius, at: center).map { $0 * viewport.height / 2 }
    }

    /// The projection a share of the way to another of the same kind and depth range: each bound
    /// `self · (1 − share) + other · share`, a bound the two share kept as it is, so a share of 0 gives
    /// this projection and a share of 1 the other exactly. For shares between 0 and 1 the result is
    /// always a valid projection; an infinite far plane mixed with a finite one stays infinite. Two
    /// projections of different kinds or depth ranges, or a share outside 0 to 1 whose bounds make no
    /// view volume, give no mix: this projection below a share of 1 and the other from 1 on.
    public func interpolated(to other: Self, at share: Scalar) -> Self {
        if share == 0 { return self }
        if share == 1 { return other }
        let step = share < 1 ? self : other
        guard kind == other.kind, depth == other.depth else { return step }
        func along(_ a: Scalar, _ b: Scalar) -> Scalar { a == b ? a : a * (1 - share) + b * share }
        do throws(Error) {
            return try Self(
                kind,
                left: along(left, other.left),
                right: along(right, other.right),
                bottom: along(bottom, other.bottom),
                top: along(top, other.top),
                near: along(near, other.near),
                far: along(far, other.far),
                depth: depth
            )
        } catch {
            return step
        }
    }
}

extension Projection {

    public static func orthographic(
        width: Scalar,
        height: Scalar,
        near: Scalar,
        far: Scalar,
        depth: Depth
    ) throws(Error) -> Self {
        try Self(
            .orthographic,
            left: -width / 2,
            right: width / 2,
            bottom: -height / 2,
            top: height / 2,
            near: near,
            far: far,
            depth: depth
        )
    }
}

extension Projection where Scalar: Trigonometry.Circular {

    public static func perspective(
        fieldOfView: Radian<Scalar>,
        aspect: Scalar,
        near: Scalar,
        far: Scalar,
        depth: Depth
    ) throws(Error) -> Self {
        let top = near * Scalar.tan(fieldOfView.underlying / 2)
        let right = top * aspect
        return try Self(
            .perspective,
            left: -right,
            right: right,
            bottom: -top,
            top: top,
            near: near,
            far: far,
            depth: depth
        )
    }
}

extension Projection where Scalar: Trigonometry.Circular {

    /// The focal length: the distance from the eye at which a window of `height` fills the vertical field
    /// of view, `height / 2 / tan(fieldOfView / 2)`, in the unit of `height`. For a viewport height in pixels
    /// it is the focal length in pixels, so a length `l` at distance `d` spans `l · focal / d` pixels.
    public static func focal(fieldOfView: Radian<Scalar>, height: Scalar) -> Scalar {
        height / 2 / Scalar.tan(fieldOfView.underlying / 2)
    }

    /// The vertical field of view in which a window of `height` at distance `focal` fills the view,
    /// `2 · atan(height / 2 / focal)`: the inverse of `focal(fieldOfView:height:)`.
    public static func field(focal: Scalar, height: Scalar) -> Radian<Scalar> {
        Radian(_unchecked: 2 * Scalar.atan(height / 2 / focal))
    }
}

#if !hasFeature(Embedded)
    extension Projection {
        private enum CodingKeys: String, CodingKey {
            case kind, left, right, bottom, top, near, far, depth
        }
    }

    extension Projection: Encodable where Scalar: Encodable {
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
            try container.encode(bottom, forKey: .bottom)
            try container.encode(top, forKey: .top)
            try container.encode(near, forKey: .near)
            try container.encode(far, forKey: .far)
            try container.encode(depth, forKey: .depth)
        }
    }

    extension Projection: Decodable where Scalar: Decodable {
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            do {
                try self.init(
                    try container.decode(Kind.self, forKey: .kind),
                    left: try container.decode(Scalar.self, forKey: .left),
                    right: try container.decode(Scalar.self, forKey: .right),
                    bottom: try container.decode(Scalar.self, forKey: .bottom),
                    top: try container.decode(Scalar.self, forKey: .top),
                    near: try container.decode(Scalar.self, forKey: .near),
                    far: try container.decode(Scalar.self, forKey: .far),
                    depth: try container.decode(Depth.self, forKey: .depth)
                )
            } catch let error as Projection.Error {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "A projection requires a finite, non-empty view volume: \(error)"
                    )
                )
            }
        }
    }
#endif
