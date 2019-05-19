import Foundation

struct FrameworkProduct {
    let framework: Framework
    let tmpDirUrl: URL
    let tmpFrameworkUrl: URL
    let tmpSymbolsUrl: URL
    let installDirUrl: URL
    let installFrameworkUrl: URL
    let installSymbolsUrl: URL

    init(
        for framework: Framework,
        with platform: Platform,
        tmpDirUrl: URL = Constants.temporaryFrameworksUrl,
        installDirUrl: URL = URL(fileURLWithPath: Constants.dependenciesPath)
        ) {
        let frameworkSubPath = "\(platform.rawValue)/\(framework.libraryName).framework"

        self.framework = framework
        
        self.tmpDirUrl = tmpDirUrl
        self.tmpFrameworkUrl = tmpDirUrl.appendingPathComponent(frameworkSubPath)
        self.tmpSymbolsUrl = tmpFrameworkUrl.appendingPathExtension("dSYM")

        self.installDirUrl = installDirUrl
        self.installFrameworkUrl = installDirUrl.appendingPathComponent(frameworkSubPath)
        self.installSymbolsUrl = installFrameworkUrl.appendingPathExtension("dSYM")
    }
    
    // This is a workaround for issues with frameworks that symlink to themselves (first found in RxSwift)
    func cleanupRecursiveFrameworkIfNeeded() throws {
        let recursiveFrameworkPath: String = tmpFrameworkUrl.appendingPathComponent(tmpFrameworkUrl.lastPathComponent).path
        if FileManager.default.fileExists(atPath: recursiveFrameworkPath) {
            try FileManager.default.removeItem(atPath: recursiveFrameworkPath)
        }
    }
}
