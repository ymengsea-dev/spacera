import Foundation

/// The built-in cleanup rules, in priority order: specific rules come before general ones, so that
/// for example Homebrew's cache is reported as "Package caches" rather than as generic "Caches".
enum BuiltinRules {
    static let all: [CleanupRule] = [
        xcodeDerivedData, xcodeDeviceSupport, unavailableSimulators, xcodeArchives,
        packageCaches, nodeModules,
        userCaches, userLogs,
        leftovers,
        iosBackups, mailDownloads, oldDownloads, largeFiles(),
        trash, dockerDiskImage, timeMachineSnapshots,
    ]

    // MARK: Developer

    static let xcodeDerivedData = CleanupRule(
        id: "xcode.derivedData", title: "Xcode DerivedData", symbol: "hammer", category: .developer, safety: .safe,
        explanation: "Intermediate build files. Xcode rebuilds them the next time you build; the first build will be slower."
    ) { ctx in
        await children(of: ctx.homePath("Library/Developer/Xcode/DerivedData"), ctx, rule: "xcode.derivedData", safety: .safe, owner: "com.apple.dt.Xcode")
    }

    static let xcodeDeviceSupport = CleanupRule(
        id: "xcode.deviceSupport", title: "Device Support Files", symbol: "iphone", category: .developer, safety: .safe,
        explanation: "Debug symbols copied from devices you've connected. Xcode copies them again if you reconnect a device with that OS version."
    ) { ctx in
        var items: [CleanupItem] = []
        for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
            items += await children(of: ctx.homePath("Library/Developer/Xcode/\(platform) DeviceSupport"), ctx,
                                    rule: "xcode.deviceSupport", safety: .safe, owner: "com.apple.dt.Xcode")
        }
        return items
    }

    static let unavailableSimulators = CleanupRule(
        id: "xcode.unavailableSimulators", title: "Unavailable Simulators", symbol: "ipad.and.iphone", category: .developer, safety: .safe,
        explanation: "Simulators for OS versions that are no longer installed. They can't be launched any more."
    ) { ctx in
        guard let json = ctx.commands.run("/usr/bin/xcrun", ["simctl", "list", "devices", "--json"]),
              let udids = parseUnavailableSimulators(json)
        else { return [] }
        var items: [CleanupItem] = []
        for udid in udids {
            if let node = await ctx.trees.node(atPath: ctx.homePath("Library/Developer/CoreSimulator/Devices/\(udid)")) {
                items.append(CleanupItem(node: node, ruleID: "xcode.unavailableSimulators", safety: .safe, ownerBundleID: "com.apple.dt.Xcode"))
            }
        }
        return items
    }

    static let xcodeArchives = CleanupRule(
        id: "xcode.archives", title: "Xcode Archives", symbol: "archivebox", category: .developer, safety: .review,
        explanation: "Builds you archived for distribution. Keep the ones you may need to symbolicate crash reports."
    ) { ctx in
        // Archives are grouped by date: Archives/2025-10-01/App.xcarchive
        guard let folder = await ctx.trees.node(atPath: ctx.homePath("Library/Developer/Xcode/Archives")) else { return [] }
        return folder.children.filter(\.isDirectory).flatMap { day in
            day.children.filter { $0.name.hasSuffix(".xcarchive") }.map {
                CleanupItem(node: $0, ruleID: "xcode.archives", safety: .review, ownerBundleID: "com.apple.dt.Xcode")
            }
        }
    }

    /// Package-manager caches. Each tool downloads the files again when it needs them.
    static let packageCacheLocations: [(path: String, tool: String)] = [
        ("Library/Caches/Homebrew", "Homebrew"),
        (".npm/_cacache", "npm"),
        ("Library/pnpm/store", "pnpm"),
        ("Library/Caches/Yarn", "Yarn"),
        ("Library/Caches/pip", "pip"),
        ("Library/Caches/CocoaPods", "CocoaPods"),
        ("Library/Caches/org.swift.swiftpm", "Swift Package Manager"),
        (".gradle/caches", "Gradle"),
        (".cargo/registry/cache", "Cargo"),
        ("Library/Caches/go-build", "Go"),
        (".m2/repository", "Maven"),
    ]

    static let packageCaches = CleanupRule(
        id: "dev.packageCaches", title: "Package Manager Caches", symbol: "shippingbox", category: .developer, safety: .safe,
        explanation: "Downloaded packages kept by tools like Homebrew, npm, and pip. They're downloaded again when needed."
    ) { ctx in
        var items: [CleanupItem] = []
        for location in packageCacheLocations {
            if let node = await ctx.trees.node(atPath: ctx.homePath(location.path)), node.size > 0 {
                items.append(CleanupItem(node: node, ruleID: "dev.packageCaches", safety: .safe, note: location.tool))
            }
        }
        return items
    }

    static let nodeModules = CleanupRule(
        id: "dev.nodeModules", title: "node_modules Folders", symbol: "cube.box", category: .developer, safety: .review,
        explanation: "JavaScript dependencies inside your projects. Run your package manager's install command to restore them."
    ) { ctx in
        guard let scan = ctx.scan else { return [] }
        let library = ScanResult.logicalPath(ctx.homePath("Library"))
        var items: [CleanupItem] = []
        scan.root.walk { node in
            guard node.isDirectory else { return false }
            if node.name == ".Trash" || node.name.hasSuffix(".app") { return false }
            if node.name == "node_modules" {
                let path = ScanResult.logicalPath(node.path)
                if !path.hasPrefix(library + "/"), node.size > 0 {
                    let project = node.parent?.name ?? ""
                    items.append(CleanupItem(node: node, ruleID: "dev.nodeModules", safety: .review, note: project))
                }
                return false // only the outermost node_modules
            }
            return true
        }
        return items
    }

    // MARK: Caches and logs

    static let userCaches = CleanupRule(
        id: "system.userCaches", title: "App Caches", symbol: "internaldrive", category: .system, safety: .safe,
        explanation: "Temporary files apps keep to work faster. Apps recreate them as needed. Quit an app before clearing its cache."
    ) { ctx in
        await children(of: ctx.homePath("Library/Caches"), ctx, rule: "system.userCaches", safety: .safe, ownerFromName: true)
    }

    static let userLogs = CleanupRule(
        id: "system.userLogs", title: "Logs", symbol: "doc.text", category: .system, safety: .safe,
        explanation: "Diagnostic logs written by apps. Only useful when troubleshooting."
    ) { ctx in
        await children(of: ctx.homePath("Library/Logs"), ctx, rule: "system.userLogs", safety: .safe, ownerFromName: true)
    }

    // MARK: Leftovers

    static let leftovers = CleanupRule(
        id: "leftovers", title: "Leftovers from Deleted Apps", symbol: "trash.slash", category: .leftovers, safety: .review,
        explanation: "Data and background items from apps that are no longer installed."
    ) { ctx in
        (ctx.attribution?.leftovers ?? []).flatMap { group in
            group.entries.map { entry in
                var item = CleanupItem(entry: entry, app: nil)
                item.ruleID = "leftovers"
                item.note = [group.displayName, entry.note].compactMap { $0 }.joined(separator: " · ")
                return item
            }
        }
    }

    // MARK: Your files

    static let iosBackups = CleanupRule(
        id: "user.iosBackups", title: "iPhone & iPad Backups", symbol: "iphone.gen3", category: .user, safety: .userData,
        explanation: "Local device backups made by Finder. Removing one means you can't restore from it. Check that you have an iCloud or newer backup first."
    ) { ctx in
        await children(of: ctx.homePath("Library/Application Support/MobileSync/Backup"), ctx, rule: "user.iosBackups", safety: .userData)
    }

    static let mailDownloads = CleanupRule(
        id: "user.mailDownloads", title: "Mail Attachments", symbol: "paperclip", category: .user, safety: .review,
        explanation: "Copies of attachments you opened in Mail. The originals stay in your email."
    ) { ctx in
        await children(of: ctx.homePath("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"), ctx,
                       rule: "user.mailDownloads", safety: .review, owner: "com.apple.mail")
    }

    static let oldDownloadsAge: TimeInterval = 90 * 24 * 60 * 60

    static let oldDownloads = CleanupRule(
        id: "user.oldDownloads", title: "Old Downloads", symbol: "arrow.down.circle", category: .user, safety: .review,
        explanation: "Items in Downloads that haven't changed in more than 90 days."
    ) { ctx in
        guard let folder = await ctx.trees.node(atPath: ctx.homePath("Downloads")) else { return [] }
        let cutoff = ctx.now.timeIntervalSince1970 - oldDownloadsAge
        return folder.children.filter { node in
            if case .smallFiles = node.kind { return false }
            return node.modificationTime > 0 && node.modificationTime < cutoff && !node.name.hasPrefix(".")
        }.map { CleanupItem(node: $0, ruleID: "user.oldDownloads", safety: .review) }
    }

    static func largeFiles(threshold: Int64 = 1_000_000_000) -> CleanupRule {
        CleanupRule(
            id: "user.largeFiles", title: "Large Files", symbol: "doc.zipper", category: .user, safety: .userData,
            explanation: "Single files larger than \(ByteCountFormatter.string(fromByteCount: threshold, countStyle: .file)) in your own folders. Check each one before removing it."
        ) { ctx in
            guard let scan = ctx.scan else { return [] }
            let home = ScanResult.logicalPath(ctx.locations.home.path)
            // App data in ~/Library (game files, VM disks, databases) belongs to apps. It's shown on
            // each app's page instead; listing it file by file here would invite breaking those apps.
            let library = home + "/Library"
            var items: [CleanupItem] = []
            scan.root.walk { node in
                if node.size < threshold { return false } // nothing below can be large enough
                if node.isDirectory {
                    if ScanResult.logicalPath(node.path) == library { return false }
                    // Skip app bundles, packages, and system areas.
                    let skip = node.name.hasSuffix(".app") || node.name.hasSuffix(".photoslibrary") || node.name == ".Trash"
                        || node.name == "Mobile Documents" || node.name == "CloudStorage"
                    return !skip
                }
                let path = ScanResult.logicalPath(node.path)
                if node.kind == .file, path.hasPrefix(home + "/"), node.name != "Docker.raw" {
                    items.append(CleanupItem(node: node, ruleID: "user.largeFiles", safety: .userData))
                }
                return false
            }
            return items
        }
    }

    // MARK: Information only

    static let trash = CleanupRule(
        id: "info.trash", title: "Trash", symbol: "trash", category: .system, safety: .infoOnly,
        explanation: "Items already in the Trash still use space until you empty it in Finder."
    ) { ctx in
        guard let node = await ctx.trees.node(atPath: ctx.homePath(".Trash")), node.size > 0 else { return [] }
        return [CleanupItem(node: node, ruleID: "info.trash", safety: .infoOnly)]
    }

    static let dockerDiskImage = CleanupRule(
        id: "info.dockerDiskImage", title: "Docker Disk Image", symbol: "shippingbox.circle", category: .developer, safety: .infoOnly,
        explanation: "Docker keeps all images and containers in one disk file. Shrink it from Docker Desktop (Settings › Resources) or with “docker system prune”. Never delete the file directly."
    ) { ctx in
        let candidates = [
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.qcow2",
        ]
        var items: [CleanupItem] = []
        for relative in candidates {
            if let node = await ctx.trees.node(atPath: ctx.homePath(relative)) {
                items.append(CleanupItem(node: node, ruleID: "info.dockerDiskImage", safety: .infoOnly, ownerBundleID: "com.docker.docker"))
            }
        }
        return items
    }

    static let timeMachineSnapshots = CleanupRule(
        id: "info.timeMachineSnapshots", title: "Time Machine Local Snapshots", symbol: "clock.arrow.circlepath", category: .system, safety: .infoOnly,
        explanation: "macOS keeps these snapshots on your disk and deletes them automatically when it needs space. Their size isn't reported individually."
    ) { ctx in
        guard let output = ctx.commands.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]) else { return [] }
        return parseSnapshots(output).map {
            CleanupItem(path: "snapshot:\($0)", size: 0, ruleID: "info.timeMachineSnapshots", safety: .infoOnly, note: $0)
        }
    }

    // MARK: Helpers

    static func children(of folderPath: String, _ ctx: RuleContext, rule: String, safety: SafetyLevel,
                         owner: String? = nil, ownerFromName: Bool = false) async -> [CleanupItem] {
        guard let folder = await ctx.trees.node(atPath: folderPath) else { return [] }
        return folder.children.compactMap { node in
            if node.name.hasPrefix(".") || node.size == 0 { return nil }
            if case .smallFiles = node.kind { return nil }
            let ownerID = owner ?? (ownerFromName && AppFootprintResolver.looksLikeBundleID(node.name) ? node.name : nil)
            return CleanupItem(node: node, ruleID: rule, safety: safety, ownerBundleID: ownerID)
        }
    }

    /// UDIDs of simulators whose runtime is missing, from `xcrun simctl list devices --json`.
    static func parseUnavailableSimulators(_ json: String) -> [String]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = root["devices"] as? [String: [[String: Any]]]
        else { return nil }
        return devices.values.flatMap { $0 }.compactMap { device in
            (device["isAvailable"] as? Bool) == false ? device["udid"] as? String : nil
        }.sorted()
    }

    /// Snapshot names from `tmutil listlocalsnapshots /`, such as "com.apple.TimeMachine.2025-11-03-101500.local".
    static func parseSnapshots(_ output: String) -> [String] {
        output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("com.apple.TimeMachine.") }
    }
}
