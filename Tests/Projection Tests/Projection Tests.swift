import Foundation
public import Projection
import Testing

extension Double: @retroactive Trigonometry.Circular {
    public static func sin(_ x: Double) -> Double { Foundation.sin(x) }
    public static func cos(_ x: Double) -> Double { Foundation.cos(x) }
    public static func tan(_ x: Double) -> Double { Foundation.tan(x) }
    public static func asin(_ x: Double) -> Double { Foundation.asin(x) }
    public static func acos(_ x: Double) -> Double { Foundation.acos(x) }
    public static func atan(_ x: Double) -> Double { Foundation.atan(x) }
    public static func atan2(_ y: Double, _ x: Double) -> Double { Foundation.atan2(y, x) }
}

enum `Projection Tests` {}

extension `Projection Tests` {
    @Suite
    struct `Projection contracts` {
        private typealias Volume = (left: Double, right: Double, bottom: Double, top: Double, near: Double, far: Double)

        private let volume: Volume = (-2, 6, -1, 3, 0.5, 40)

        private func projection(
            _ kind: Projection<Double>.Kind,
            _ depth: Projection<Double>.Depth,
            far: Double? = nil
        ) throws -> Projection<Double> {
            try Projection(
                kind,
                left: volume.left,
                right: volume.right,
                bottom: volume.bottom,
                top: volume.top,
                near: volume.near,
                far: far ?? volume.far,
                depth: depth
            )
        }

        private func close(_ a: Point<3, Double>?, _ b: Point<3, Double>, _ tolerance: Double = 1e-12) -> Bool {
            guard let a else { return false }
            return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance && abs(a.z - b.z) <= tolerance
        }

        @Test(arguments: Projection<Double>.Kind.allCases, Projection<Double>.Depth.allCases)
        func `The corners of the view volume map to the corners of the normalised volume`(
            kind: Projection<Double>.Kind,
            depth: Projection<Double>.Depth
        ) throws {
            let projection = try projection(kind, depth)
            for (plane, normalizedZ) in [(volume.near, depth.range.lowerBound), (volume.far, depth.range.upperBound)] {
                let spread = kind == .perspective ? plane / volume.near : 1
                for (x, normalizedX) in [(volume.left, -1.0), (volume.right, 1.0)] {
                    for (y, normalizedY) in [(volume.bottom, -1.0), (volume.top, 1.0)] {
                        let eye = Point<3, Double>(x: x * spread, y: y * spread, z: -plane)
                        let expected = Point<3, Double>(x: normalizedX, y: normalizedY, z: normalizedZ)
                        #expect(close(projection.normalized(eye), expected))
                        #expect(close(projection.eye(expected), eye, 1e-9))
                    }
                }
            }
        }

        @Test(arguments: Projection<Double>.Kind.allCases, Projection<Double>.Depth.allCases)
        func `Unprojecting a projected point returns it`(
            kind: Projection<Double>.Kind,
            depth: Projection<Double>.Depth
        ) throws {
            let projection = try projection(kind, depth)
            for point in [
                Point<3, Double>(x: 0.25, y: -0.5, z: -1), Point(x: 5, y: 2.5, z: -39), Point(x: -30, y: 12, z: -7),
                Point(x: 1, y: 1, z: 3),
            ] {
                let normalized = try #require(projection.normalized(point))
                #expect(close(projection.eye(normalized), point, 1e-9))
            }
        }

        @Test(arguments: Projection<Double>.Depth.allCases)
        func `Perspective divides by the distance in front of the eye`(depth: Projection<Double>.Depth) throws {
            let projection = try projection(.perspective, depth)
            let point = Point<3, Double>(x: 1, y: 0.5, z: -4)
            #expect(projection.clip(point)[3] == 4)
            let near = try #require(projection.normalized(point))
            let far = try #require(projection.normalized(Point(x: 2, y: 1, z: -8)))
            #expect(abs(near.x - far.x) < 1e-15 && abs(near.y - far.y) < 1e-15)
            #expect(near.z < far.z)
            #expect(projection.clip(Point(x: 1, y: 1, z: 0))[3] == 0)
            #expect(projection.normalized(Point(x: 1, y: 1, z: 0)) == nil)
            #expect(projection.clip(Point(x: 0, y: 0, z: 2))[3] == -2)
        }

        @Test(arguments: Projection<Double>.Depth.allCases)
        func `Orthographic projection is affine and keeps parallel lines parallel`(
            depth: Projection<Double>.Depth
        ) throws {
            let projection = try projection(.orthographic, depth)
            let a = Point<3, Double>(x: 1, y: 0.5, z: -4)
            let b = Point<3, Double>(x: 1, y: 0.5, z: -30)
            #expect(projection.clip(a)[3] == 1)
            #expect(projection.clip(Point(x: 0, y: 0, z: 100))[3] == 1)
            let first = try #require(projection.normalized(a))
            let second = try #require(projection.normalized(b))
            #expect(first.x == second.x && first.y == second.y)
            #expect(first.z < second.z)
            let middle = try #require(projection.normalized(Point(x: 1, y: 0.5, z: -17)))
            #expect(abs(middle.z - (first.z + second.z) / 2) < 1e-15)
        }

        @Test(arguments: Projection<Double>.Depth.allCases)
        func `An infinite far plane puts infinity at the upper depth bound`(
            depth: Projection<Double>.Depth
        ) throws {
            let projection = try projection(.perspective, depth, far: .infinity)
            let near = try #require(projection.normalized(Point(x: 0, y: 0, z: -volume.near)))
            #expect(near.z == depth.range.lowerBound)
            var previous = near.z
            for distance in [1.0, 10, 1e3, 1e6] {
                let z = try #require(projection.normalized(Point(x: 0, y: 0, z: -distance))).z
                #expect(z > previous && z < 1)
                previous = z
            }
            #expect(projection.eye(Point(x: 0, y: 0, z: 1)) == nil)
            let point = Point<3, Double>(x: 3, y: -2, z: -25)
            #expect(close(projection.eye(try #require(projection.normalized(point))), point, 1e-9))
        }

        @Test
        func `Clip coordinates are the coefficient rows applied to the homogeneous point`() throws {
            for kind in Projection<Double>.Kind.allCases {
                let projection = try projection(kind, .unit)
                let rows = projection.coefficients
                let point = Point<3, Double>(x: 0.75, y: -1.5, z: -9)
                let clip = projection.clip(point)
                (0..<4).forEach { row in
                    var expected = 0.0
                    (0..<3).forEach { column in expected += rows[row][column] * point[column] }
                    expected += rows[row][3]
                    #expect(clip[row] == expected)
                }
            }
        }

        @Test
        func `An empty, non-finite or misplaced view volume is rejected`() {
            typealias P = Projection<Double>
            #expect(throws: P.Error.empty) {
                try P(.perspective, left: 1, right: 1, bottom: -1, top: 1, near: 1, far: 2, depth: .unit)
            }
            #expect(throws: P.Error.empty) {
                try P(.orthographic, left: -1, right: 1, bottom: 2, top: 1, near: 1, far: 2, depth: .unit)
            }
            #expect(throws: P.Error.empty) {
                try P(.orthographic, left: -1, right: 1, bottom: -1, top: 1, near: 2, far: 2, depth: .unit)
            }
            #expect(throws: P.Error.nonfinite) {
                try P(.perspective, left: -.infinity, right: 1, bottom: -1, top: 1, near: 1, far: 2, depth: .unit)
            }
            #expect(throws: P.Error.nonfinite) {
                try P(.perspective, left: -1, right: 1, bottom: -1, top: .nan, near: 1, far: 2, depth: .unit)
            }
            #expect(throws: P.Error.nonfinite) {
                try P(.orthographic, left: -1, right: 1, bottom: -1, top: 1, near: 1, far: .infinity, depth: .unit)
            }
            #expect(throws: P.Error.nonfinite) {
                try P(.perspective, left: -1, right: 1, bottom: -1, top: 1, near: 1, far: -.infinity, depth: .unit)
            }
            #expect(throws: P.Error.behindEye) {
                try P(.perspective, left: -1, right: 1, bottom: -1, top: 1, near: 0, far: 2, depth: .unit)
            }
            #expect(throws: P.Error.behindEye) {
                try P(.perspective, left: -1, right: 1, bottom: -1, top: 1, near: -3, far: 2, depth: .unit)
            }
            #expect(throws: Never.self) {
                try P(.orthographic, left: -1, right: 1, bottom: -1, top: 1, near: -3, far: 2, depth: .unit)
            }
        }

        @Test
        func `A field of view gives a centred window whose half height is near times the tangent`() throws {
            let projection = try Projection<Double>.perspective(
                fieldOfView: .pi.half,
                aspect: 2,
                near: 0.5,
                far: 100,
                depth: .symmetric
            )
            #expect(projection.kind == .perspective)
            #expect(abs(projection.top - 0.5) < 1e-15)
            #expect(projection.bottom == -projection.top)
            #expect(projection.right == projection.top * 2)
            #expect(projection.left == -projection.right)
            #expect(close(projection.normalized(Point(x: 0, y: 3, z: -3)), Point(x: 0, y: 1, z: (100.5 * 3 - 100) / 99.5 / 3)))
            #expect(throws: Projection<Double>.Error.empty) {
                try Projection<Double>.perspective(fieldOfView: .zero, aspect: 1, near: 1, far: 2, depth: .unit)
            }
            #expect(throws: Projection<Double>.Error.empty) {
                try Projection<Double>.perspective(
                    fieldOfView: Radian(_unchecked: 4),
                    aspect: 1,
                    near: 1,
                    far: 2,
                    depth: .unit
                )
            }
        }

        @Test
        func `A centred orthographic box spans its width and height about the axis`() throws {
            let projection = try Projection<Double>.orthographic(width: 8, height: 2, near: 0, far: 5, depth: .unit)
            #expect(projection.left == -4 && projection.right == 4)
            #expect(projection.bottom == -1 && projection.top == 1)
            #expect(projection.normalized(Point(x: 4, y: -1, z: -5)) == Point(x: 1, y: -1, z: 1))
            #expect(projection.normalized(Point(x: 0, y: 0, z: 0)) == Point(x: 0, y: 0, z: 0))
        }

        @Test
        func `Depth ranges are as named`() {
            #expect(Projection<Double>.Depth.symmetric.range == -1...1)
            #expect(Projection<Double>.Depth.unit.range == 0...1)
        }

        @Test
        func `Value conformances and coding keep the validated volume`() throws {
            func requireSendable<T: Sendable>(_ value: T) {}
            let projection = try projection(.perspective, .unit)
            requireSendable(projection)
            #expect(Set([projection, projection, try self.projection(.orthographic, .unit)]).count == 2)
            let data = try JSONEncoder().encode(projection)
            #expect(try JSONDecoder().decode(Projection<Double>.self, from: data) == projection)
            let invalid = Data(
                #"{"kind":"perspective","left":1,"right":1,"bottom":0,"top":1,"near":1,"far":2,"depth":"unit"}"#.utf8
            )
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(Projection<Double>.self, from: invalid) }
        }

        @Test(arguments: [0.1, 0.6, 1.2, 2.5])
        func `The focal length and the field of view are inverse for a viewport height`(fieldOfView: Double) {
            let focalLength = Projection<Double>.focal(fieldOfView: Radian(_unchecked: fieldOfView), height: 1080)
            #expect(abs(Projection<Double>.field(focal: focalLength, height: 1080).underlying - fieldOfView) < 1e-12)
            let back = Projection<Double>.focal(
                fieldOfView: Projection<Double>.field(focal: 1500, height: 1080),
                height: 1080
            )
            #expect(abs(back - 1500) < 1e-9)
        }

        @Test
        func `The focal length scales a length at a distance into the viewport`() throws {
            let fieldOfView = Radian<Double>(_unchecked: 0.7)
            let focalLength = Projection<Double>.focal(fieldOfView: fieldOfView, height: 1080)
            let projection = try Projection<Double>.perspective(
                fieldOfView: fieldOfView,
                aspect: 16.0 / 9.0,
                near: 1,
                far: 100,
                depth: .unit
            )
            let distance = 8.0
            let span = 0.5
            let normalized = try #require(projection.normalized(Point(x: 0, y: span, z: -distance)))
            #expect(abs(normalized.y * 1080 / 2 - span * focalLength / distance) < 1e-9)
            #expect(abs(Projection<Double>.focal(fieldOfView: .init(_unchecked: Double.pi / 2), height: 1080) - 540) < 1e-9)
        }
    }
}

extension `Projection Tests` {
    @Suite
    struct `Unprojection, ball radius and interpolation` {
        private func projection(
            _ kind: Projection<Double>.Kind,
            _ depth: Projection<Double>.Depth,
            far: Double = 40
        ) throws -> Projection<Double> {
            try Projection(kind, left: -2, right: 6, bottom: -1, top: 3, near: 0.5, far: far, depth: depth)
        }

        @Test(arguments: Projection<Double>.Kind.allCases, Projection<Double>.Depth.allCases)
        func `Projecting the unprojected point gives the normalised point back over a grid`(
            kind: Projection<Double>.Kind,
            depth: Projection<Double>.Depth
        ) throws {
            let projection = try projection(kind, depth)
            let steps = stride(from: -1.5, through: 1.5, by: 0.25)
            for x in steps {
                for y in steps {
                    for distance in [0.5, 1, 7.3, 40, 250] {
                        let eye = projection.eye(Point(x: x, y: y), distance: distance)
                        #expect(eye.z == -distance)
                        let back = try #require(projection.normalized(eye))
                        #expect(abs(back.x - x) <= 1e-12 && abs(back.y - y) <= 1e-12)
                    }
                }
            }
        }

        @Test(arguments: Projection<Double>.Kind.allCases, Projection<Double>.Depth.allCases)
        func `Unprojecting at the point's own distance returns the point`(
            kind: Projection<Double>.Kind,
            depth: Projection<Double>.Depth
        ) throws {
            let projection = try projection(kind, depth)
            for point in [
                Point<3, Double>(x: 0.25, y: -0.5, z: -1), Point(x: 5, y: 2.5, z: -39), Point(x: -30, y: 12, z: -7),
                Point(x: 1, y: 1, z: 3),
            ] {
                let normalized = try #require(projection.normalized(point))
                let back = projection.eye(Point(x: normalized.x, y: normalized.y), distance: -point.z)
                #expect(abs(back.x - point.x) <= 1e-12 * 30 && abs(back.y - point.y) <= 1e-12 * 30 && back.z == point.z)
                let full = try #require(projection.eye(normalized))
                #expect(abs(full.x - back.x) <= 1e-9 && abs(full.y - back.y) <= 1e-9)
            }
        }

        @Test(arguments: [
            Point<3, Double>(x: 0, y: 0, z: -5), Point(x: 3, y: 0, z: -5), Point(x: -7, y: 0, z: -4), Point(x: 2, y: 0, z: -1.5),
        ])
        func `A ball's perspective radius is half the width of its projected silhouette`(center: Point<3, Double>) throws {
            let projection = try projection(.perspective, .unit)
            let radius = 1.0
            let measured = try #require(projection.radius(of: radius, at: center))
            let distance = center.coordinates.length
            let axis = center.coordinates.scaled(by: 1 / distance)
            let foot = center.coordinates.scaled(by: 1 - radius * radius / (distance * distance))
            let rim = radius * (distance * distance - radius * radius).squareRoot() / distance
            let first = Vector<3, Double>(x: 0, y: 1, z: 0)
            let second = axis.cross(first)
            var (lowest, highest) = (Double.infinity, -Double.infinity)
            for angle in stride(from: 0, to: 2 * Double.pi, by: Double.pi / 3600) {
                let point = foot + first.scaled(by: rim * cos(angle)) + second.scaled(by: rim * sin(angle))
                let projected = try #require(projection.normalized(Point(coordinates: point)))
                lowest = min(lowest, projected.y)
                highest = max(highest, projected.y)
            }
            #expect(abs((highest - lowest) / 2 - measured) <= 1e-6 * measured)
            if center.x == 0 {
                let alpha = asin(radius / distance)
                #expect(abs(measured - projection.coefficients[1][1] * tan(alpha)) <= 1e-12)
            }
        }

        @Test
        func `A ball's orthographic radius is its radius at the vertical scale`() throws {
            let projection = try projection(.orthographic, .symmetric)
            let center = Point<3, Double>(x: 3, y: -1, z: 20)
            let measured = try #require(projection.radius(of: 2, at: center))
            let top = try #require(projection.normalized(Point(x: 3, y: 1, z: 20)))
            let bottom = try #require(projection.normalized(Point(x: 3, y: -3, z: 20)))
            #expect(abs((top.y - bottom.y) / 2 - measured) <= 1e-15)
        }

        @Test
        func `A ball's radius has none for a ball reaching the eye's plane or a bad radius`() throws {
            let perspective = try projection(.perspective, .unit)
            #expect(perspective.radius(of: 1, at: Point(x: 0, y: 0, z: -1)) == nil)
            #expect(perspective.radius(of: 1, at: Point(x: 5, y: 0, z: 0.5)) == nil)
            #expect(perspective.radius(of: -1, at: Point(x: 0, y: 0, z: -5)) == nil)
            #expect(perspective.radius(of: .nan, at: Point(x: 0, y: 0, z: -5)) == nil)
            #expect(perspective.radius(of: 0, at: Point(x: 0, y: 0, z: -5)) == 0)
            let viewport = try Projection<Double>.Viewport(x: 0, y: 0, width: 1920, height: 1080, direction: .down)
            let normalized = try #require(perspective.radius(of: 1, at: Point(x: 0, y: 0, z: -5)))
            #expect(perspective.radius(of: 1, at: Point(x: 0, y: 0, z: -5), in: viewport) == normalized * 540)
        }

        @Test
        func `Interpolation gives the ends at 0 and 1 and the middle bounds at a half`() throws {
            let first = try projection(.perspective, .unit)
            let second = try Projection<Double>(.perspective, left: -4, right: 2, bottom: -3, top: 1, near: 1.5, far: 40, depth: .unit)
            #expect(first.interpolated(to: second, at: 0) == first)
            #expect(first.interpolated(to: second, at: 1) == second)
            let middle = first.interpolated(to: second, at: 0.5)
            #expect(middle == (try Projection(.perspective, left: -3, right: 4, bottom: -2, top: 2, near: 1, far: 40, depth: .unit)))
            #expect(first.interpolated(to: first, at: 0.3) == first)
        }

        @Test
        func `Interpolation between kinds or depth ranges steps at 1`() throws {
            let perspective = try projection(.perspective, .unit)
            let orthographic = try projection(.orthographic, .unit)
            let symmetric = try projection(.perspective, .symmetric)
            #expect(perspective.interpolated(to: orthographic, at: 0.5) == perspective)
            #expect(perspective.interpolated(to: orthographic, at: 0.999) == perspective)
            #expect(perspective.interpolated(to: orthographic, at: 1) == orthographic)
            #expect(perspective.interpolated(to: symmetric, at: 0.5) == perspective)
            #expect(perspective.interpolated(to: symmetric, at: 1) == symmetric)
        }

        @Test
        func `Interpolation keeps an infinite far plane and steps where no volume results`() throws {
            let finite = try projection(.perspective, .unit)
            let infinite = try projection(.perspective, .unit, far: .infinity)
            #expect(finite.interpolated(to: infinite, at: 0) == finite)
            #expect(finite.interpolated(to: infinite, at: 0.5).far == .infinity)
            #expect(finite.interpolated(to: infinite, at: 1) == infinite)
            let wide = try Projection<Double>(.perspective, left: -2, right: 6, bottom: -1, top: 3, near: 30, far: 40, depth: .unit)
            #expect(finite.interpolated(to: wide, at: -1) == finite)
            #expect(finite.interpolated(to: wide, at: 3) == wide)
        }
    }
}
