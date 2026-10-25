import Foundation
import GamePresentation

/// Decision 397: the saves' folder in the player's own iCloud, the app's
/// iCloud Drive container, `Saves/` (not under `Documents/`: the saves are
/// the game's, not files the player sees in Files). The device's saves
/// folder stays the one the game reads and writes; ``SaveSync`` keeps this
/// one in step with it. Every read and write is coordinated with iCloud's
/// own (`NSFileCoordinator`), and a file iCloud has not brought to the
/// device yet is asked for and listed as not there yet.
struct ICloudSaveFolder: SaveSyncFolder {
    let directory: URL
    /// The iCloud account's token, archived and fingerprinted: another
    /// account signed in on the device gives another.
    let owner: UInt64?

    /// The folder, or `nil`: no iCloud account, iCloud Drive off for the
    /// app, or a build without the iCloud entitlement (the container is
    /// then `nil` too). Takes a moment the first time: never on the main
    /// thread.
    static func current() -> ICloudSaveFolder? {
        let manager = FileManager.default
        guard let token = manager.ubiquityIdentityToken,
              let container = manager.url(forUbiquityContainerIdentifier: nil) else { return nil }
        let archived = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
        return ICloudSaveFolder(
            directory: container.appendingPathComponent("Saves", isDirectory: true),
            owner: archived.map(SaveSync.fingerprint)
        )
    }

    func files() throws -> [String: SaveSyncFolderFile] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [:] }
        let urls = try manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey], options: []
        )
        var files: [String: SaveSyncFolderFile] = [:]
        for url in urls {
            let name = url.lastPathComponent
            // An older system lists a file not brought down yet as a
            // stand-in, `.<name>.icloud`, which ``SaveSync`` reads as that
            // file, not there yet.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = directory.appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                try? manager.startDownloadingUbiquitousItem(at: real)
                files[name] = SaveSyncFolderFile(isAvailable: false)
                continue
            }
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsUploadedKey])
            let status = values?.ubiquitousItemDownloadingStatus
            // Only the latest version is compared: an older one on the
            // device would read as changed here.
            let isCurrent = status == nil || status == .current
            if !isCurrent {
                try? manager.startDownloadingUbiquitousItem(at: url)
            }
            // Decision 397, later: written here but not yet up in iCloud
            // (offline, or going up), so the list says it waits.
            files[name] = SaveSyncFolderFile(isAvailable: isCurrent, isUploaded: values?.ubiquitousItemIsUploaded ?? true)
        }
        return files
    }

    func read(_ name: String) throws -> Data {
        try coordinated(name, writing: false) { try Data(contentsOf: $0) }
    }

    func write(_ data: Data, to name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try coordinated(name, writing: true) { try data.write(to: $0, options: .atomic) }
    }

    func remove(_ name: String) throws {
        try coordinated(name, writing: true, options: .forDeleting) { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    func otherVersions(of name: String) -> [Data] {
        let url = directory.appendingPathComponent(name)
        return (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).compactMap { version in
            try? coordinated(name, writing: false) { _ in try Data(contentsOf: version.url) }
        }
    }

    func discardOtherVersions(of name: String) {
        let url = directory.appendingPathComponent(name)
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            version.isResolved = true
        }
        try? coordinated(name, writing: true) { try NSFileVersion.removeOtherVersionsOfItem(at: $0) }
    }

    /// Runs `body` on file `name` while iCloud keeps off it.
    private func coordinated<T>(
        _ name: String, writing: Bool, options: NSFileCoordinator.WritingOptions = .forReplacing, _ body: (URL) throws -> T
    ) throws -> T {
        let url = directory.appendingPathComponent(name)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
                result = Result { try body(url) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
                result = Result { try body(url) }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
