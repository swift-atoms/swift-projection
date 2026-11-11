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
