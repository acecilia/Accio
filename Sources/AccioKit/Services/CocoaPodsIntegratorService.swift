import Foundation
import Version

enum CocoaPodsIntegratorServiceError: Error {
    case frameworkPlistNotFound
    case versionKeyNotFoundInFrameworkPlist
    case versionInFrameworkPlistNotValid
}

final class CocoaPodsIntegratorService {
    private static let groupName = "accio_integrated_pods"
    private static let newLineWithIndentation = "\n    "

    static let shared = CocoaPodsIntegratorService(workingDirectory: GlobalOptions.workingDirectory.value ?? FileManager.default.currentDirectoryPath)

    private let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func updateDependencies(_ frameworkProducts: [FrameworkProduct], _ appTarget: AppTarget, for platform: Platform) throws {
        try generatePodspecFiles(frameworkProducts, appTarget, for: platform)
        try integrateInPodfile(frameworkProducts, appTarget, for: platform)
    }

    private func generatePodspecFiles(_ frameworkProducts: [FrameworkProduct], _ appTarget: AppTarget, for platform: Platform) throws {
        for frameworkProduct in frameworkProducts {
            let podspecContent = try generatePodspec(frameworkProduct)
            let podspecPath = frameworkProduct.installFrameworkUrl.deletingPathExtension().appendingPathExtension("podspec")
            try podspecContent.write(toFile: podspecPath.path, atomically: false, encoding: .utf8)
        }
    }

    private func integrateInPodfile(_ frameworkProducts: [FrameworkProduct], _ appTarget: AppTarget, for platform: Platform) throws {
        var localPods: [String] = []
        for frameworkProduct in frameworkProducts {
            let podspecParentPath = frameworkProduct.installFrameworkUrl.deletingLastPathComponent().relativePath
            localPods.append("pod '\(frameworkProduct.framework.libraryName)', :path => '\(podspecParentPath)'")
        }
        localPods = localPods.sorted()

        let podfilePath = "\(workingDirectory)/Podfile"
        var podfile = try String(contentsOf: URL(fileURLWithPath: podfilePath))
        let targetPattern = "target\\s+'\(appTarget.targetName)'\\s+do"
        let groupPattern = "def\\s+\(CocoaPodsIntegratorService.groupName)[\\S\\s]+?end\\b"

        // Add the cocoapods group if not found
        if try NSRegularExpression(pattern: groupPattern).matches(podfile) == false {
            let template = """
            def \(CocoaPodsIntegratorService.groupName)
            end

            target '\(appTarget.targetName)' do
            """
            let targetRegex = try NSRegularExpression(pattern: targetPattern)
            podfile = targetRegex.stringByReplacingMatches(in: podfile, range: podfile.fullNSRange, withTemplate: template)
        }

        // Update the cocoapods group
        let template = """
        def \(CocoaPodsIntegratorService.groupName)
            \(localPods.joined(separator: CocoaPodsIntegratorService.newLineWithIndentation))
        end
        """
        let groupRegex = try NSRegularExpression(pattern: groupPattern)
        podfile = groupRegex.stringByReplacingMatches(in: podfile, range: podfile.fullNSRange, withTemplate: template)

        // Add the cocoapods group to the target if not found
        if try NSRegularExpression(pattern: "\(targetPattern)[\\S\\s]+\(CocoaPodsIntegratorService.groupName)").matches(podfile) == false {
            let template = """
            target '\(appTarget.targetName)' do
                \(CocoaPodsIntegratorService.groupName)
            """
            let targetRegex = try NSRegularExpression(pattern: targetPattern)
            podfile = targetRegex.stringByReplacingMatches(in: podfile, range: podfile.fullNSRange, withTemplate: template)
        }

        try podfile.write(toFile: podfilePath, atomically: false, encoding: .utf8)
    }

    private func generatePodspec(_ frameworkProduct: FrameworkProduct) throws -> String {
        // Get the dependency strings to be added to the podspec
        var dependencies = try frameworkProduct.framework.requiredFrameworks.map {
            "s.dependency '\($0.libraryName)', '\(try $0.version ?? getVersionFor(frameworkProduct))'"
        }

        // Add blank lines around the dependencies in case there are any
        if dependencies.isEmpty == false {
            dependencies.insert("", at: 0)
            dependencies.append("")
        }

        let version = try frameworkProduct.framework.version ?? getVersionFor(frameworkProduct)
        let dependenciesString = dependencies.joined(separator: CocoaPodsIntegratorService.newLineWithIndentation)
        return """
        Pod::Spec.new do |s|
            s.name                   = '\(frameworkProduct.framework.libraryName)'
            s.version                = '\(version)'
            s.vendored_frameworks    = '\(frameworkProduct.framework.libraryName).framework'
            \(dependenciesString)
            # Dummy data required by cocoapods
            s.authors                = 'dummy'
            s.summary                = 'dummy'
            s.homepage               = 'dummy'
            s.license                = { :type => 'MIT' }
            s.source                 = { :git => '' }
        end
        """
    }

    /// When the manifest points to a dependency without using a version number (ex: using a branch name),
    /// then the version is unknown. In order to work around this, it is possible to obtain the version
    /// stored in the `Info.plist` file, inside the `.framework` file
    private func getVersionFor(_ frameworkProduct: FrameworkProduct) throws -> Version {
        let plistPath = frameworkProduct.installFrameworkUrl.appendingPathComponent("Info.plist")
        guard let plistContent = NSDictionary(contentsOfFile: plistPath.path) else {
            throw CocoaPodsIntegratorServiceError.frameworkPlistNotFound
        }

        guard let versionString = plistContent["CFBundleShortVersionString"] as? String else {
            throw CocoaPodsIntegratorServiceError.versionKeyNotFoundInFrameworkPlist
        }

        guard let version = Version(tolerant: versionString) else {
            throw CocoaPodsIntegratorServiceError.versionInFrameworkPlistNotValid
        }

        return version
    }
}
