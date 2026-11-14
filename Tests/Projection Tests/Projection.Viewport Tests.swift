import Foundation
import Projection
import Testing

extension `Projection Tests` {
    @Suite
    struct `Viewport contracts` {
        @Test(arguments: Projection<Double>.Viewport.Direction.allCases)
        func `The normalised corners land on the viewport's corners`(direction: Projection<Double>.Viewport.Direction) throws {
            let viewport = try Projection<Double>.Viewport(x: 10, y: 20, width: 640, height: 480, direction: direction)
            let (least, greatest) = direction == .down ? (20.0, 500.0) : (500.0, 20.0)
            #expect(viewport.point(Point(x: -1, y: 1)) == Point(x: 10, y: least))
            #expect(viewport.point(Point(x: 1, y: -1)) == Point(x: 650, y: greatest))
            #expect(viewport.point(Point(x: 0, y: 0)) == Point(x: 330, y: 260))
        }

        @Test(arguments: Projection<Double>.Viewport.Direction.allCases)
        func `The viewport map and its inverse round trip`(direction: Projection<Double>.Viewport.Direction) throws {
            let viewport = try Projection<Double>.Viewport(x: -3.5, y: 7, width: 1920, height: 1080, direction: direction)
            for x in stride(from: -1.5, through: 1.5, by: 0.125) {
                for y in stride(from: -1.5, through: 1.5, by: 0.125) {
                    let normalized = viewport.normalized(viewport.point(Point(x: x, y: y)))
                    #expect(abs(normalized.x - x) <= 1e-15 && abs(normalized.y - y) <= 1e-15)
                    let point = Point<2, Double>(x: x * 1000, y: y * 700)
                    let back = viewport.point(viewport.normalized(point))
                    #expect(abs(back.x - point.x) <= 1e-12 && abs(back.y - point.y) <= 1e-12)
                }
            }
        }

        @Test
        func `An empty or non-finite viewport is rejected, and coding keeps a valid one`() throws {
            typealias V = Projection<Double>.Viewport
            #expect(throws: Projection<Double>.Error.empty) { try V(x: 0, y: 0, width: 0, height: 1, direction: .down) }
            #expect(throws: Projection<Double>.Error.empty) { try V(x: 0, y: 0, width: 1, height: -1, direction: .up) }
            #expect(throws: Projection<Double>.Error.nonfinite) { try V(x: .nan, y: 0, width: 1, height: 1, direction: .up) }
            #expect(throws: Projection<Double>.Error.nonfinite) { try V(x: 0, y: 0, width: .infinity, height: 1, direction: .up) }
            let viewport = try V(x: 1, y: 2, width: 3, height: 4, direction: .down)
            #expect(try JSONDecoder().decode(V.self, from: try JSONEncoder().encode(viewport)) == viewport)
            let invalid = Data(#"{"x":0,"y":0,"width":0,"height":1,"direction":"down"}"#.utf8)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(V.self, from: invalid) }
        }
    }
}
