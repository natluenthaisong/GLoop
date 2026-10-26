import AppKit

/// In-app updates from GitHub Releases. The check sends no identity: one anonymous
/// HTTPS request for the public releases list. Only stable, notarized releases
/// signed by the same team as the running app are ever installed.
struct ReleaseVersion: Comparable, CustomStringConvertible {
    let parts: [Int]
    init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        if let dash = value.firstIndex(of: "-") { value = String(value[..<dash]) }
        let numbers = value.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 4, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.map { $0! }
    }
    static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        for i in 0..<max(a.parts.count,b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return false
    }
    static func == (a: ReleaseVersion, b: ReleaseVersion) -> Bool { !(a < b) && !(b < a) }
    var description: String { parts.map(String.init).joined(separator: ".") }
}

struct ReleaseInfo {
    let version: ReleaseVersion
    let tag: String
    let page: URL
    let archive: URL
    let archiveName: String
    let checksums: URL?
    let notes: String
}

enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

final class Updater {
    static let repository = "natluenthaisong/GLoop"
    static let feed = ProcessInfo.processInfo.environment["GLOOP_UPDATE_FEED"].flatMap(URL.init(string:)) ?? URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
    static let automaticKey = "updateCheckAutomatically", checkedKey = "updateCheckedAt", skippedKey = "updateSkippedTag"
    /// Only a test feed (GLOOP_UPDATE_FEED) may point at local files; real releases must be https.
    static var allowLocalFeed: Bool { ProcessInfo.processInfo.environment["GLOOP_UPDATE_FEED"] != nil }
    static func trusted(_ url: URL) -> Bool { url.scheme == "https" || (allowLocalFeed && url.scheme == "file") }
    static var current: ReleaseVersion { ReleaseVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") ?? ReleaseVersion("0")! }
    static var automatic: Bool {
        get { UserDefaults.standard.object(forKey: automaticKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: automaticKey) }
    }
    weak var app: PlayerApp?
    var busy = false
    var progressObservation: NSKeyValueObservation?
    init(app: PlayerApp) { self.app = app }

    /// Pick the newest stable release with an Apple Silicon archive that is newer than `current`.
    static func select(_ data: Data, current: ReleaseVersion, skipping skipped: String? = nil) throws -> ReleaseInfo? {
        guard let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw UpdateError.message("The release list could not be read.") }
        var best: ReleaseInfo?
        for release in releases {
            guard release["draft"] as? Bool != true, release["prerelease"] as? Bool != true,
                  let tag = release["tag_name"] as? String, let version = ReleaseVersion(tag), version > current, tag != skipped,
                  let page = (release["html_url"] as? String).flatMap(URL.init(string:)), trusted(page),
                  let assets = release["assets"] as? [[String: Any]] else { continue }
            func asset(_ match: (String) -> Bool) -> (String, URL)? {
                for item in assets {
                    if let name = item["name"] as? String, match(name), let link = (item["browser_download_url"] as? String).flatMap(URL.init(string:)), trusted(link) { return (name, link) }
                }
                return nil
            }
            guard let archive = asset({ $0.range(of: #"^GLoop-[0-9][0-9.]*-macOS-arm64\.zip$"#, options: .regularExpression) != nil }) else { continue }
            if best == nil || version > best!.version {
                best = ReleaseInfo(version: version, tag: tag, page: page, archive: archive.1, archiveName: archive.0, checksums: asset({ $0 == "SHA256SUMS.txt" })?.1, notes: (release["body"] as? String ?? "").prefix(4000).description)
            }
        }
        return best
    }
    /// The first paragraph of the release notes as plain text for the sheet.
    static func plainSummary(_ notes: String) -> String {
        for line in notes.split(whereSeparator: \.isNewline) {
            var text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("#"), !text.hasPrefix("-"), !text.hasPrefix("*") else { continue }
            for marker in ["**", "`", "__"] { text = text.replacingOccurrences(of: marker, with: "") }
            return String(text.prefix(400))
        }
        return ""
    }
    static func expectedDigest(in checksums: String, for name: String) -> String? {
        for line in checksums.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 2, fields.last.map({ String($0).trimmingCharacters(in: CharacterSet(charactersIn: "*")) }) == name, fields[0].count == 64 { return String(fields[0]).lowercased() }
        }
        return nil
    }
    static func sha256(_ url: URL) throws -> String {
        let output = try run("/usr/bin/shasum", ["-a", "256", url.path])
        return String(output.split(separator: " ").first ?? "").lowercased()
    }
    static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice; process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw UpdateError.message(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return text
    }
    static func teamIdentifier(_ app: URL) -> String? {
        guard let text = try? run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path]) else { return nil }
        return text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst("TeamIdentifier=".count)) }
    }
    static func bundleIdentifier(_ app: URL) -> String? {
        (try? PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any])?["CFBundleIdentifier"] as? String
    }

    func check(manual: Bool) {
        guard let app, !busy else { return }
        busy = true
        if manual { app.status.stringValue = "Checking for updates…" }
        var request = URLRequest(url: Self.feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GLoop/\(Self.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, let app = self.app else { return }
                self.busy = false
                UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Self.checkedKey)
                do {
                    if let error { throw error }
                    guard let data, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { throw UpdateError.message("GitHub did not return the release list.") }
                    let skipped = manual ? nil : UserDefaults.standard.string(forKey: Self.skippedKey)
                    if let release = try Self.select(data, current: Self.current, skipping: skipped) { self.offer(release, manual: manual) }
                    else if manual { app.status.stringValue = "GLoop \(Self.current) is up to date."; self.inform("GLoop is up to date", "Version \(Self.current) is the newest release.") }
                } catch {
                    if manual { app.status.stringValue = "Update check failed."; self.inform("Could not check for updates", error.localizedDescription + "\n\nYou can also download releases from GitHub.") }
                }
            }
        }.resume()
    }
    func inform(_ title: String, _ text: String) {
        guard let app, app.window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text; alert.beginSheetModal(for: app.window)
    }
    func offer(_ release: ReleaseInfo, manual: Bool) {
        guard let app else { return }
        guard app.window.attachedSheet == nil, app.downloadJob == nil else { if manual { app.status.stringValue = "GLoop \(release.version) is available. Finish the current import, then check again." }; return }
        app.status.stringValue = "GLoop \(release.version) is available."
        let alert = NSAlert(); alert.messageText = "GLoop \(release.version) is available"
        let summary = Self.plainSummary(release.notes)
        alert.informativeText = "You have \(Self.current). The update is downloaded from GitHub, checked against its published checksum, signature and notarization, then installed in place. Your library, settings and practice history stay where they are.\n\n" + (summary.isEmpty ? "" : summary + "\n\n") + "Release notes: \(release.page.absoluteString)"
        alert.addButton(withTitle: "Install and Relaunch"); alert.addButton(withTitle: "Later"); alert.addButton(withTitle: "Skip This Version")
        alert.beginSheetModal(for: app.window) { [weak self] answer in
            switch answer {
            case .alertFirstButtonReturn: self?.install(release)
            case .alertThirdButtonReturn: UserDefaults.standard.set(release.tag, forKey: Self.skippedKey); app.status.stringValue = "Skipped GLoop \(release.version). Check for Updates… shows it again."
            default: app.status.stringValue = "Ready"
            }
        }
    }
    /// Download, verify (checksum, signature, same team, notarization), swap the bundle and relaunch.
    func install(_ release: ReleaseInfo) {
        guard let app, !busy else { return }
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app", FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            inform("Cannot update in place", "GLoop cannot replace itself at \(bundle.path). Download \(release.archiveName) from \(release.page.absoluteString) and replace the app manually."); return
        }
        busy = true
        app.status.stringValue = "Downloading GLoop \(release.version)…"
        let task = URLSession.shared.downloadTask(with: release.archive) { [weak self] location, response, error in
            let result = Result { () -> URL in
                if let error { throw error }
                guard let location, (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { throw UpdateError.message("The update could not be downloaded.") }
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent("GLoop-update-\(UUID().uuidString).zip")
                try FileManager.default.moveItem(at: location, to: kept); return kept
            }
            DispatchQueue.main.async { [weak self] in self?.downloaded(result, release: release, bundle: bundle) }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async { self?.app?.status.stringValue = String(format: "Downloading GLoop \(release.version)… %.0f%%", progress.fractionCompleted * 100) }
        }
        task.resume()
    }
    private func downloaded(_ result: Result<URL, Error>, release: ReleaseInfo, bundle: URL) {
        progressObservation = nil
        guard let app else { return }
        let staging = bundle.deletingLastPathComponent().appendingPathComponent(".GLoop-update-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            let archive = try result.get()
            defer { try? FileManager.default.removeItem(at: archive); try? FileManager.default.removeItem(at: staging) }
            app.status.stringValue = "Verifying GLoop \(release.version)…"
            if let checksums = release.checksums {
                let text = try String(contentsOf: checksums, encoding: .utf8)
                guard let expected = Self.expectedDigest(in: text, for: release.archiveName) else { throw UpdateError.message("The release has no checksum for \(release.archiveName).") }
                guard try Self.sha256(archive) == expected else { throw UpdateError.message("The downloaded file does not match its published checksum. Nothing was changed.") }
            } else { throw UpdateError.message("The release has no SHA256SUMS.txt. Nothing was changed.") }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            _ = try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
            let candidate = staging.appendingPathComponent("GLoop.app")
            guard FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Contents/MacOS/GLoop").path) else { throw UpdateError.message("The archive does not contain GLoop.app.") }
            _ = try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
            guard Self.bundleIdentifier(candidate) == Bundle.main.bundleIdentifier else { throw UpdateError.message("The downloaded app has a different bundle identifier. Nothing was changed.") }
            guard let mine = Self.teamIdentifier(bundle), mine != "not set", Self.teamIdentifier(candidate) == mine else { throw UpdateError.message("The downloaded app is not signed by the same developer. Nothing was changed.") }
            if !app.uiTest { _ = try Self.run("/usr/sbin/spctl", ["--assess", "--type", "execute", candidate.path]) }
            let retired = bundle.deletingLastPathComponent().appendingPathComponent(".GLoop-previous-\(UUID().uuidString.prefix(8)).app")
            try FileManager.default.moveItem(at: bundle, to: retired)
            do { try FileManager.default.moveItem(at: candidate, to: bundle) }
            catch { try? FileManager.default.moveItem(at: retired, to: bundle); throw error }
            try? FileManager.default.trashItem(at: retired, resultingItemURL: nil)
            try? FileManager.default.removeItem(at: retired)
            app.status.stringValue = "GLoop \(release.version) installed. Relaunching…"
            let relaunch = Process(); relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"", bundle.path]
            busy = false
            if app.uiTest { app.updateInstalledForTest = true } else { try relaunch.run(); NSApp.terminate(nil) }
        } catch {
            busy = false
            app.status.stringValue = "Update not installed."
            inform("Could not install the update", error.localizedDescription + "\n\nThe current version keeps running. You can download \(release.archiveName) from \(release.page.absoluteString).")
        }
    }
    static func selfTest() throws {
        precondition(ReleaseVersion("v3.5.1")! > ReleaseVersion("3.5.0")! && ReleaseVersion("3.10.0")! > ReleaseVersion("3.9.9")! && ReleaseVersion("v3.5.0-rc.1")! == ReleaseVersion("3.5.0")!)
        precondition(ReleaseVersion("") == nil && ReleaseVersion("v3..1") == nil && ReleaseVersion("abc") == nil && ReleaseVersion("3.5.0.1.2") == nil)
        let feed = """
        [{"tag_name":"v9.0.0","draft":true,"prerelease":false,"html_url":"https://github.com/x/y/releases/tag/v9.0.0","assets":[{"name":"GLoop-9.0.0-macOS-arm64.zip","browser_download_url":"https://github.com/x/y/releases/download/v9.0.0/GLoop-9.0.0-macOS-arm64.zip"}]},
         {"tag_name":"v3.6.0-rc.1","draft":false,"prerelease":true,"html_url":"https://github.com/x/y/releases/tag/v3.6.0-rc.1","assets":[{"name":"GLoop-3.6.0-candidate-macOS-arm64.zip","browser_download_url":"https://github.com/x/y/a.zip"}]},
         {"tag_name":"v3.5.2","draft":false,"prerelease":false,"html_url":"https://github.com/x/y/releases/tag/v3.5.2","body":"# Title\\nFixes loops.\\n","assets":[{"name":"GLoop-3.5.2-macOS-arm64.zip","browser_download_url":"https://github.com/x/y/releases/download/v3.5.2/GLoop-3.5.2-macOS-arm64.zip"},{"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/x/y/releases/download/v3.5.2/SHA256SUMS.txt"}]},
         {"tag_name":"v3.5.3","draft":false,"prerelease":false,"html_url":"http://github.com/x/y/releases/tag/v3.5.3","assets":[{"name":"GLoop-3.5.3-macOS-arm64.zip","browser_download_url":"https://github.com/x/y/b.zip"}]},
         {"tag_name":"v3.5.4","draft":false,"prerelease":false,"html_url":"https://github.com/x/y/releases/tag/v3.5.4","assets":[{"name":"GLoop-3.5.4-macOS-x86_64.zip","browser_download_url":"https://github.com/x/y/c.zip"}]},
         {"tag_name":"v2.2.0","draft":false,"prerelease":false,"html_url":"https://github.com/x/y/releases/tag/v2.2.0","assets":[{"name":"GLoop-2.2.0-macOS-arm64.zip","browser_download_url":"https://github.com/x/y/releases/download/v2.2.0/GLoop-2.2.0-macOS-arm64.zip"}]}]
        """
        let data = Data(feed.utf8)
        let pick = try select(data, current: ReleaseVersion("3.5.1")!)
        precondition(pick?.tag == "v3.5.2" && pick?.archiveName == "GLoop-3.5.2-macOS-arm64.zip" && pick?.checksums != nil, "Drafts, previews, non-https pages, other architectures and older versions must be ignored")
        let none = try select(data, current: ReleaseVersion("3.5.2")!), skippedPick = try select(data, current: ReleaseVersion("3.5.1")!, skipping: "v3.5.2")
        precondition(none == nil && skippedPick == nil)
        let old = try select(data, current: ReleaseVersion("2.0.0")!); precondition(old?.tag == "v3.5.2")
        precondition(expectedDigest(in: "abcd  other.zip\n" + String(repeating: "a", count: 64) + "  GLoop-3.5.2-macOS-arm64.zip\n", for: "GLoop-3.5.2-macOS-arm64.zip") == String(repeating: "a", count: 64))
        precondition(expectedDigest(in: "short  GLoop-3.5.2-macOS-arm64.zip\n", for: "GLoop-3.5.2-macOS-arm64.zip") == nil)
        do { _ = try select(Data("{}".utf8), current: ReleaseVersion("1")!); preconditionFailure("Non-list feed accepted") } catch is UpdateError {}
        precondition(plainSummary("# Title\n\n- **bullet** first\nGLoop **3.6** adds `things`.\nMore\n") == "GLoop 3.6 adds things.")
        precondition(plainSummary("## Only headings\n- and bullets\n") == "")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("GLoop-sha-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let digest = try sha256(file); precondition(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        print("PASS updater: version ordering, release selection (stable, arm64, https, newer, not skipped), checksum parsing and hashing")
    }
}
