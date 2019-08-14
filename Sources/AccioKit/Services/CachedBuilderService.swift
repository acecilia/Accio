import Foundation

enum CachedBuilderServiceError: Error {
    case unableToRetrieveSwiftVersion
    case swiftVersionChanged
}

extension CachedBuilderServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unableToRetrieveSwiftVersion:
            return "Unable to retrieve Swift version used for command line."

        case .swiftVersionChanged:
            return "Swift version used for command line apparently changed during runtime."
        }
    }
}

final class CachedBuilderService {
    private let frameworkCachingService: FrameworkCachingService
    private let carthageBuilderService: CarthageBuilderService

    init(sharedCachePath: String?) {
        frameworkCachingService = FrameworkCachingService(sharedCachePath: sharedCachePath)
        carthageBuilderService = CarthageBuilderService(frameworkCachingService: frameworkCachingService)
    }

    func frameworkProducts(
        manifest: Manifest,
        appTarget: AppTarget,
        dependencyGraph: DependencyGraph,
        platform: Platform,
        swiftVersion: String
    ) throws -> [BuiltFramework] {
        var frameworkProducts: [BuiltFramework] = []

        let frameworks = try appTarget.frameworkDependencies(manifest: manifest, dependencyGraph: dependencyGraph).flattenedDeepFirstOrder()
        let frameworksWithoutDuplicates: [Framework] = frameworks.reduce(into: []) { result, framework in
            if !result.contains(framework) { result.append(framework) }
        }

        for framework in frameworksWithoutDuplicates {
            if
                let cachedFrameworkProduct = try frameworkCachingService.cachedProduct(
                    framework: framework,
                    platform: platform,
                    swiftVersion: swiftVersion
                )
            {
                frameworkProducts.append(cachedFrameworkProduct)
            } else {
                let builtFramework: BuiltFramework
                switch try InstallationTypeDetectorService.shared.detectInstallationType(for: framework) {
                case .swiftPackageManager:
                    try XcodeProjectGeneratorService.shared.generateXcodeProject(framework: framework)
                    builtFramework = try carthageBuilderService.build(
                        framework: framework,
                        platform: platform,
                        swiftVersion: swiftVersion,
                        alreadyBuiltFrameworkProducts: frameworkProducts
                    )

                case .carthage:
                    try GitResetService.shared.resetGit(atPath: framework.projectDirectory, includeUntrackedFiles: false)
                    builtFramework = try carthageBuilderService.build(
                        framework: framework,
                        platform: platform,
                        swiftVersion: swiftVersion,
                        alreadyBuiltFrameworkProducts: frameworkProducts
                    )
                }

                if
                    let frameworkSwiftVersion = (
                        try? SwiftVersionDetectorService.shared.detectSwiftVersion(ofFrameworkProduct: builtFramework.product)
                    ) ?? (
                        try? SwiftVersionDetectorService.shared.getCurrentSwiftVersion()
                    )
                {
                    // If detectSwiftVersion doesn't work (e. g. happening for RxAtomic because of missing Swift header file),
                    // fallback to just retrieving current swift version via bash command.
                    guard frameworkSwiftVersion == swiftVersion else {
                        throw CachedBuilderServiceError.swiftVersionChanged
                    }
                } else {
                    throw CachedBuilderServiceError.unableToRetrieveSwiftVersion
                }

                frameworkProducts.append(builtFramework)
            }
        }

        return frameworkProducts
    }
}
