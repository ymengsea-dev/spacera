import Foundation
import Testing
@testable import Spacera

struct SafetyGuardTests {
    let guardrail = SafetyGuard.standard(home: "/Users/test", appBundle: "/Applications/Spacera.app")

    @Test(arguments: [
        "/", "/System", "/System/Library/CoreServices/Finder.app", "/usr/bin/swift", "/bin/sh", "/sbin/mount",
        "/private/var/db/receipts", "/etc/hosts", "/var/log", "/Volumes/USB/file", "/Library/Apple/thing",
        "/Applications", "/Library", "/Users", "/Users/Shared",
        "/Users/test", "/Users/test/Library", "/Users/test/Documents", "/Users/test/Desktop", "/Users/test/Downloads",
        "/Users/test/Pictures", "/Users/test/.Trash",
        "/Users/test/Library/Caches", "/Users/test/Library/Containers", "/Users/test/Library/Application Support",
        "/Library/Caches", "/Library/Application Support",
        "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/report.pdf",
        "/Users/test/Library/CloudStorage/Dropbox/file.txt",
        "/Users/test/Library/Keychains/login.keychain-db",
        "/Users/test/Library/Mail/V10/INBOX.mbox",
        "/Users/test/Library/Messages/chat.db",
        "/Users/test/Pictures/Photos Library.photoslibrary/database",
        "/Applications/Spacera.app", "/Users/test/Library/Application Support/Spacera/actions.json",
        "/Users/other/Library/Caches/x", "/Users/test/Library/Caches/../../Documents/x",
        "relative/path", "",
    ])
    func blocksProtectedPaths(_ path: String) {
        #expect(!guardrail.check(path).isAllowed, "\(path) should be blocked")
    }

    @Test(arguments: [
        "/Users/test/Library/Caches/com.vendor.app",
        "/Users/test/Library/Containers/com.vendor.app",
        "/Users/test/Library/Application Support/Vendor App",
        "/Users/test/Library/Developer/Xcode/DerivedData/Project-abc",
        "/Users/test/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/1234",
        "/Users/test/Downloads/old.dmg",
        "/Users/test/code/project/node_modules",
        "/Users/test/.npm/_cacache",
        "/Library/Application Support/com.vendor.daemon",
        "/Library/LaunchDaemons/com.vendor.helper.plist",
        "/Applications/Some Thirdparty.app",
    ])
    func allowsOrdinaryItems(_ path: String) {
        #expect(guardrail.check(path) == .allowed, "\(path) should be allowed")
    }

    @Test func symlinkedFolderCannotRedirectIntoProtectedArea() throws {
        let tree = try TempTree()
        let protected = try tree.directory("protected")
        try tree.file("protected/precious.txt", bytes: 10)
        try tree.directory("home/Library/Caches")
        try tree.symlink("home/Library/Caches/sneaky", pointingTo: protected)

        let guardrail = SafetyGuardTests.testGuard(tree, extraProtected: [protected.path])

        // The item inside the symlinked folder resolves to the protected folder: blocked.
        #expect(!guardrail.check(tree.url("home/Library/Caches/sneaky/precious.txt").path).isAllowed)
        // Trashing the symlink itself only moves the link, so that's allowed.
        #expect(guardrail.check(tree.url("home/Library/Caches/sneaky").path) == .allowed)
    }

    @Test func blocksAppleAppsEvenInApplicationsFolder() throws {
        let tree = try TempTree()
        let apple = try tree.app("Apps/Safari.app", bundleID: "com.apple.Safari")
        let other = try tree.app("Apps/Other.app", bundleID: "com.other.app")
        let guardrail = SafetyGuardTests.testGuard(tree)
        #expect(!guardrail.check(apple.path).isAllowed)
        #expect(guardrail.check(other.path) == .allowed)
    }

    /// A guard that treats the temporary tree as the only allowed area. The standard guard blocks
    /// /private and /var, where temporary folders live.
    static func testGuard(_ tree: TempTree, extraProtected: [String] = []) -> SafetyGuard {
        let standard = SafetyGuard.standard(home: tree.url("home").path)
        let root = SafetyGuard.normalize(tree.root.path)
        return SafetyGuard(
            home: standard.home,
            allowedRoots: [root],
            protectedPrefixes: standard.protectedPrefixes.filter { $0 != "/private" && $0 != "/var" } + extraProtected.map(SafetyGuard.normalize),
            protectedExactPaths: standard.protectedExactPaths.union([root]),
            protectedChildrenOf: standard.protectedChildrenOf
        )
    }
}
