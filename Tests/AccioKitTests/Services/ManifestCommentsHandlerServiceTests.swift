@testable import AccioKit
import XCTest

class ManifestCommentsHandlerServiceTests: XCTestCase {
    private let testResourcesDir: URL = FileManager.userCacheDirUrl.appendingPathComponent("AccioTestResources")
    private let possibleLinkageValues = ["default"]
    private let possibleIntegrationValues = ["binary"]
    private let manifestResourceTopContent = """
                // swift-tools-version:4.2
                import PackageDescription

                let package = Package(
                    name: "TestProject",
                    products: [],
                    dependencies: [
                        .package(url: "https://github.com/Flinesoft/HandySwift.git", .upToNextMajor(from: "2.8.0")),
                        .package(url: "https://github.com/Flinesoft/HandyUIKit.git", .upToNextMajor(from: "1.9.0")),
                        .package(url: "https://github.com/Flinesoft/Imperio.git", .upToNextMajor(from: "3.0.0")),
                        .package(url: "https://github.com/JamitLabs/MungoHealer.git", .upToNextMajor(from: "0.3.0")),
                        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "1.6.2")),
                    ],
    """

    private var manifestResourceWithoutComments: Resource {
        return Resource(
            url: testResourcesDir.appendingPathComponent("Package.swift"),
            contents: """
                \(manifestResourceTopContent)
                    targets: [
                        .target(
                            name: "TestProject-iOS",
                            dependencies: [
                              "HandySwift",
                              "HandyUIKit",
                              "Imperio",
                              "MungoHealer",
                              "SwiftyBeaver",
                            ],
                            path: "TestProject-iOS"
                        )
                    ]
                )

                """
        )
    }

    private var manifestResourceWithArbitraryComment: Resource {
        return Resource(
            url: testResourcesDir.appendingPathComponent("Package.swift"),
            contents: """
                \(manifestResourceTopContent)
                    targets: [
                        .target(
                            name: "TestProject-iOS",
                            dependencies: [
                              "HandySwift",
                              "HandyUIKit",
                              "Imperio",
                              "MungoHealer",
                              "SwiftyBeaver",
                            ],
                            path: "TestProject-iOS"
                            // This is an arbitrary comment
                        )
                    ]
                )

                """
        )
    }

    private var manifestResourceWithInvalidValue: Resource {
        return Resource(
            url: testResourcesDir.appendingPathComponent("Package.swift"),
            contents: """
                \(manifestResourceTopContent)
                    targets: [
                        .target(
                            name: "TestProject-iOS",
                            dependencies: [
                              "HandySwift",
                              "HandyUIKit",
                              "Imperio",
                              "MungoHealer",
                              "SwiftyBeaver",
                            ],
                            path: "TestProject-iOS"
                            // defaultLinkage: .someInvalidVale,
                        )
                    ]
                )

                """
        )
    }

    private var manifestResourceWithValidComments: Resource {
        return Resource(
            url: testResourcesDir.appendingPathComponent("Package.swift"),
            contents: """
                \(manifestResourceTopContent)
                    targets: [
                        .target(
                            name: "TestProject-iOS",
                            dependencies: [
                              "HandySwift",
                              "HandyUIKit",
                              "Imperio",
                              "MungoHealer",
                              "SwiftyBeaver",
                            ],
                            path: "TestProject-iOS"
                            // defaultLinkage: .default,
                            // customLinkage: [.default: ["SwiftyBeaver", "Imperio"]],
                            // defaultIntegration: .binary,
                            // customIntegration: [.cocoapods: ["HandySwift", "MungoHealer"], .binary: ["HandyUIKit"]],
                        )
                    ]
                )

                """
        )
    }

    override func setUp() {
        super.setUp()

        try! bash("rm -rf '\(testResourcesDir.path)'")
        try! bash("mkdir '\(testResourcesDir.path)'")
    }

    func testWithoutComments() {
        resourcesLoaded([manifestResourceWithoutComments]) {
            let sut = ManifestCommentsHandlerService(workingDirectory: testResourcesDir.path)
            let result = try! sut.getCommentsInformation()
            let expectedResult = [
                CommentInformation(
                    targetName: "TestProject-iOS",
                    defaultLinkage: nil,
                    customLinkage: [:],
                    defaultIntegration: nil,
                    customIntegration: [:]
                )
            ]
            XCTAssertEqual(result, expectedResult)
        }
    }

    func testWithArbitraryComment() {
        resourcesLoaded([manifestResourceWithArbitraryComment]) {
            let sut = ManifestCommentsHandlerService(workingDirectory: testResourcesDir.path)
            let result = try! sut.getCommentsInformation()
            let expectedResult = [
                CommentInformation(
                    targetName: "TestProject-iOS",
                    defaultLinkage: nil,
                    customLinkage: [:],
                    defaultIntegration: nil,
                    customIntegration: [:]
                )
            ]
            XCTAssertEqual(result, expectedResult)
        }
    }

    func testWithInvalidValue() {
        resourcesLoaded([manifestResourceWithInvalidValue]) {
            let expectedError = ManifestCommentsHandlerError.invalidValue(
                key: .defaultLinkage,
                value: "someInvalidVale",
                possibleValues: possibleLinkageValues
            )
            do {
                _ = try ManifestCommentsHandlerService(workingDirectory: testResourcesDir.path).getCommentsInformation()
                XCTFail("Function was expected to throw")
            } catch {
                XCTAssertEqual(error as? ManifestCommentsHandlerError, expectedError)
            }
        }
    }

    func testValidComments() {
        resourcesLoaded([manifestResourceWithValidComments]) {
            let sut = ManifestCommentsHandlerService(workingDirectory: testResourcesDir.path)
            let result = try! sut.getCommentsInformation()

            let expectedResult = CommentInformation(
                targetName: "TestProject-iOS",
                defaultLinkage: .default,
                customLinkage: [
                    "SwiftyBeaver": .default,
                    "Imperio" : .default
                ],
                defaultIntegration: .binary,
                customIntegration: [
                    "HandySwift": .cocoapods,
                    "MungoHealer": .cocoapods,
                    "HandyUIKit": .binary
                ]
            )
            XCTAssertEqual(result, [expectedResult])
        }
    }
}