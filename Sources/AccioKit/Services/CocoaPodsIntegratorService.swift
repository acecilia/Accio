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

    private let workingDirectory: String

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    func update(targetName: String, builtFrameworks: [BuiltFramework]) throws -> [BuiltFramework] {
        var cocoapodsDependencies: [BuiltFramework] = []
        try builtFrameworks.forEach {
            switch try ManifestCommentsHandlerService(workingDirectory: workingDirectory).integration(for: $0.framework.libraryName, in: targetName) {
            case .cocoapods:
                cocoapodsDependencies.append($0)

            case .binary:
                break
            }
        }

        // Only execute the cocoapods integration if needed
        if cocoapodsDependencies.isEmpty == false {
            try generatePodspecFiles(for: cocoapodsDependencies)
            try integrateInPodfile(cocoapodsDependencies, of: targetName)
        }
        return builtFrameworks.filter { cocoapodsDependencies.contains($0) == false }
    }

    private func generatePodspecFiles(for builtFrameworks: [BuiltFramework]) throws {
        for builtFramework in builtFrameworks {
            let podspecContent = try generatePodspec(for: builtFramework, with: builtFrameworks)
            let podspecPath = builtFramework.product.frameworkDirUrl.deletingPathExtension().appendingPathExtension("podspec")
            try podspecContent.write(toFile: podspecPath.path, atomically: false, encoding: .utf8)
        }
    }

    private func integrateInPodfile(_ builtFrameworks: [BuiltFramework], of targetName: String) throws {
        var localPods: [String] = []
        for builtFramework in builtFrameworks {
            let podspecParentPath = builtFramework.product.frameworkDirUrl.deletingLastPathComponent().path.replacingOccurrences(of: workingDirectory, with: ".")
            localPods.append("pod '\(builtFramework.framework.libraryName)', :path => '\(podspecParentPath)'")
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

    private func generatePodspec(for builtFramework: BuiltFramework, with builtFrameworks: [BuiltFramework]) throws -> String {
        // Get the dependency strings to be added to the podspec
        var dependencies: [String] = try builtFramework.framework.requiredFrameworks.map { dependency in
            let version = try dependency.version ?? {
                let dependencyProduct = try builtFrameworks.filter(matching: dependency).product
                return try getVersionFor(dependencyProduct)
            }()
            return "s.dependency '\(dependency.libraryName)', '\(version)'"
        }

        // Add blank lines around the dependencies in case there are any
        if dependencies.isEmpty == false {
            dependencies.insert("", at: 0)
            dependencies.append("")
        }

        let version = try builtFramework.framework.version ?? getVersionFor(builtFramework.product)
        let dependenciesString = dependencies.joined(separator: "\n    ")
        return """
        Pod::Spec.new do |s|
            s.name                   = '\(builtFramework.framework.libraryName)'
            s.version                = '\(version)'
            s.vendored_frameworks    = '\(builtFramework.framework.libraryName).framework'
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

private extension Array where Element == BuiltFramework {
    func filter(matching framework: Framework) throws -> BuiltFramework {
        guard let product = first(where: { $0.framework == framework }) else {
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
