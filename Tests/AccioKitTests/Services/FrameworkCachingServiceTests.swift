@testable import AccioKit
import XCTest

class FrameworkCachingServiceTests: XCTestCase {
    private let sharedCachePath: String = FileManager.userCacheDirUrl.appendingPathComponent("AccioTestSharedCache").path
    private let testFrameworkProduct = FrameworkProduct(
        for: Framework(projectName: "TestProject", libraryName: "Example", version: nil, projectDirectory: "", requiredFrameworks: []),
        with: .iOS,
        tmpDirUrl: FileManager.userCacheDirUrl.appendingPathComponent("AccioTestFrameworks")
    )

    override func setUp() {
        super.setUp()

        Constants.useTestPaths = true

        try! bash("rm -rf '\(Constants.localCachePath)'")
        try! bash("rm -rf '\(sharedCachePath)'")

        try! bash("mkdir -p '\(FileManager.userCacheDirUrl.appendingPathComponent("AccioTestFrameworks/iOS/Example.framework").path)'")
        try! bash("touch '\(FileManager.userCacheDirUrl.appendingPathComponent("AccioTestFrameworks/iOS/Example.framework/Example").path)'")
        try! bash("touch '\(FileManager.userCacheDirUrl.appendingPathComponent("AccioTestFrameworks/iOS/Example.framework.dSYM").path)'")
    }

    override func tearDown() {
        super.tearDown()

        try! bash("rm -rf '\(Constants.dependenciesPath)'")
    }

    func testCachingProductWithoutSharedCachePath() {
        TestHelper.shared.isStartedByUnitTests = true
        let frameworkCachingService = FrameworkCachingService(sharedCachePath: nil)

        let testFrameworkLocalCacheFilePath: String = "\(Constants.localCachePath)/\(Constants.swiftVersion)/\(testFrameworkProduct.framework.libraryName)/\(testFrameworkProduct.framework.commitHash)/\(Platform.iOS.rawValue).zip"
        let testFrameworkSharedCacheFilePath: String = "\(sharedCachePath)/\(Constants.swiftVersion)/\(testFrameworkProduct.framework.libraryName)/\(testFrameworkProduct.framework.commitHash)/\(Platform.iOS.rawValue).zip"

        var cachedProduct: FrameworkProduct? = try! frameworkCachingService.cachedProduct(framework: testFrameworkProduct.framework, platform: .iOS)
        XCTAssertNil(cachedProduct)

        XCTAssert(!FileManager.default.fileExists(atPath: testFrameworkLocalCacheFilePath))
        XCTAssert(!FileManager.default.fileExists(atPath: testFrameworkSharedCacheFilePath))

        try! frameworkCachingService.cache(product: testFrameworkProduct, platform: .iOS)

        cachedProduct = try! frameworkCachingService.cachedProduct(framework: testFrameworkProduct.framework, platform: .iOS)
        XCTAssertNotNil(cachedProduct)

        XCTAssert(cachedProduct!.tmpFrameworkUrl.path.hasPrefix(Constants.temporaryFrameworksUrl.path))
        XCTAssert(cachedProduct!.tmpSymbolsUrl.path.hasPrefix(Constants.temporaryFrameworksUrl.path))

        XCTAssert(FileManager.default.fileExists(atPath: cachedProduct!.tmpFrameworkUrl.path))
        XCTAssert(FileManager.default.fileExists(atPath: cachedProduct!.tmpSymbolsUrl.path))

        XCTAssert(FileManager.default.fileExists(atPath: testFrameworkLocalCacheFilePath))
        XCTAssert(!FileManager.default.fileExists(atPath: testFrameworkSharedCacheFilePath))
    }

    func testCachingProductWithSharedCachePath() {
        TestHelper.shared.isStartedByUnitTests = true
        let frameworkCachingService = FrameworkCachingService(sharedCachePath: sharedCachePath)

        let testFrameworkLocalCacheFilePath: String = "\(Constants.localCachePath)/\(Constants.swiftVersion)/\(testFrameworkProduct.framework.libraryName)/\(testFrameworkProduct.framework.commitHash)/\(Platform.iOS.rawValue).zip"
        let testFrameworkSharedCacheFilePath: String = "\(sharedCachePath)/\(Constants.swiftVersion)/\(testFrameworkProduct.framework.libraryName)/\(testFrameworkProduct.framework.commitHash)/\(Platform.iOS.rawValue).zip"

        var cachedProduct: FrameworkProduct? = try! frameworkCachingService.cachedProduct(framework: testFrameworkProduct.framework, platform: .iOS)
        XCTAssertNil(cachedProduct)

        XCTAssert(!FileManager.default.fileExists(atPath: testFrameworkLocalCacheFilePath))
        XCTAssert(!FileManager.default.fileExists(atPath: testFrameworkSharedCacheFilePath))

        try! frameworkCachingService.cache(product: testFrameworkProduct, platform: .iOS)

        cachedProduct = try! frameworkCachingService.cachedProduct(framework: testFrameworkProduct.framework, platform: .iOS)
        XCTAssertNotNil(cachedProduct)

        XCTAssert(cachedProduct!.tmpFrameworkUrl.path.hasPrefix(Constants.temporaryFrameworksUrl.path))
        XCTAssert(cachedProduct!.tmpSymbolsUrl.path.hasPrefix(Constants.temporaryFrameworksUrl.path))

        XCTAssert(FileManager.default.fileExists(atPath: cachedProduct!.tmpFrameworkUrl.path))
        XCTAssert(FileManager.default.fileExists(atPath: cachedProduct!.tmpSymbolsUrl.path))

        XCTAssert(!FileManager.default.fileExists(atPath: testFrameworkLocalCacheFilePath))
        XCTAssert(FileManager.default.fileExists(atPath: testFrameworkSharedCacheFilePath))
    }
}
