import Foundation
import Version

enum CocoaPodsIntegratorServiceError: Error {
    case frameworkPlistNotFound
    case versionKeyNotFoundInFrameworkPlist
    case versionInFrameworkPlistNotValid
    case frameworkDoesNotHaveProduct(Framework)
}

final class CocoaPodsIntegratorService {
    private static let groupNameSuffix = "_accio"

    static let shared = CocoaPodsIntegratorService(workingDirectory: GlobalOptions.workingDirectory.value ?? FileManager.default.currentDirectoryPath)

    private let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func update(frameworks: [Framework], of appTarget: AppTarget, with frameworkProducts: [FrameworkProduct]) throws {
        try generatePodspecFiles(for: frameworks, with: frameworkProducts)
        try integrateInPodfile(frameworks, appTarget.targetName)
    }

    private func generatePodspecFiles(for frameworks: [Framework], with frameworkProducts: [FrameworkProduct]) throws {
        for framework in frameworks {
            let podspecContent = try generatePodspec(for: framework, using: frameworkProducts)
            let product = try frameworkProducts.filter(matching: framework)
            let podspecPath = product.frameworkDirUrl.deletingPathExtension().appendingPathExtension("podspec")
            try podspecContent.write(toFile: podspecPath.path, atomically: false, encoding: .utf8)
        }
    }

    private func integrateInPodfile(_ frameworks: [Framework], _ targetName: String) throws {
        var localPods: [String] = []
        for framework in frameworks {
            // TODO: finish
            // let podspecParentPath = frameworkProduct.frameworkDirUrl.deletingLastPathComponent().path.replacingOccurrences(of: workingDirectory, with: ".")
            let podspecParentPath = URL(fileReferenceLiteralResourceName: "")
            localPods.append("pod '\(framework.libraryName)', :path => '\(podspecParentPath)'")
        }
        localPods = localPods.sorted()

        let podfilePath = "\(workingDirectory)/Podfile"
        var podfile = try String(contentsOf: URL(fileURLWithPath: podfilePath))
        let groupName = "\(targetName)\(CocoaPodsIntegratorService.groupNameSuffix)".lowercased()
        let targetPattern = "(.*?)target\\s+'\(targetName)'\\s+do"
        let groupPattern = "(.*?)def\\s+\(groupName)[\\S\\s]+?end\\b"

        // Add the cocoapods group if not found
        if try NSRegularExpression(pattern: groupPattern).matches(podfile) == false {
            let template = """
            $1def \(groupName)
            $1end

            $1target '\(targetName)' do
            """
            let targetRegex = try NSRegularExpression(pattern: targetPattern)
            podfile = targetRegex.stringByReplacingMatches(in: podfile, range: podfile.fullNSRange, withTemplate: template)
        }

        // Update the cocoapods group
        let template = """
        $1def \(groupName)
        $1    \(localPods.joined(separator: "\n$1    "))
        $1end
        """
        let groupRegex = try NSRegularExpression(pattern: groupPattern)
        podfile = groupRegex.stringByReplacingMatches(in: podfile, range: podfile.fullNSRange, withTemplate: template)

        // Add the cocoapods group to the target if not found
        if try NSRegularExpression(pattern: "\(targetPattern)[\\S\\s]+\(groupName)").matches(podfile) == false {
            let template = """
            $1target '\(targetName)' do
            $1    \(groupName)
            """
            let targetRegex = try NSRegularExpression(pattern: targetPattern)
            podfile = targetRegex.stringByReplacingMatches(in: podfile, range: podfile.fullNSRange, withTemplate: template)
        }

        try podfile.write(toFile: podfilePath, atomically: false, encoding: .utf8)
    }

    private func generatePodspec(for framework: Framework, using frameworkProducts: [FrameworkProduct]) throws -> String {
        // Get the dependency strings to be added to the podspec
        var dependencies: [String] = try framework.requiredFrameworks.map { dependency in
            let version = try dependency.version ?? {
                let dependencyProduct = try frameworkProducts.filter(matching: dependency)
                return try getVersionFor(dependencyProduct)
            }()
            return "s.dependency '\(dependency.libraryName)', '\(version)'"
        }

        // Add blank lines around the dependencies in case there are any
        if dependencies.isEmpty == false {
            dependencies.insert("", at: 0)
            dependencies.append("")
        }

        let version = try framework.version ?? getVersionFor(try frameworkProducts.filter(matching: framework))
        let dependenciesString = dependencies.joined(separator: "\n    ")
        return """
        Pod::Spec.new do |s|
            s.name                   = '\(framework.libraryName)'
            s.version                = '\(version)'
            s.vendored_frameworks    = '\(framework.libraryName).framework'
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
        let plistPath = frameworkProduct.frameworkDirUrl.appendingPathComponent("Info.plist")
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

private extension Array where Element == FrameworkProduct {
    func filter(matching framework: Framework) throws -> FrameworkProduct {
        guard let product = first(where: { $0.libraryName == framework.libraryName }) else {
            throw CocoaPodsIntegratorServiceError.frameworkDoesNotHaveProduct(framework)
        }
        return product
    }
}

// See: https://www.hackingwithswift.com/articles/108/how-to-use-regular-expressions-in-swift

private extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        let range = NSRange(location: 0, length: string.utf16.count)
        return firstMatch(in: string, options: [], range: range) != nil
    }
}
