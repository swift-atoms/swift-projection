extension Projection {
    @frozen
    public enum Error: Swift::Error, Equatable, Sendable {
        case nonfinite
        case empty
        case behindEye
    }
}
