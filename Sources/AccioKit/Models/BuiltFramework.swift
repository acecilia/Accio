import Foundation

/// A built framework, which contains the information stored on the Framework and FrameworkProduct structs
struct BuiltFramework: Equatable {
    let framework: Framework
    let product: FrameworkProduct

    init(_ framework: Framework, _ product: FrameworkProduct) {
        self.framework = framework
        self.product = product
    }
}

/// Convenient extensions
extension Array where Element == BuiltFramework {
    var frameworks: [Framework] {
        return map { $0.framework }
    }

    var products: [FrameworkProduct] {
        return map { $0.product }
    }
}
