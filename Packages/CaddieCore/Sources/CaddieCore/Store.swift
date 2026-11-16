import Foundation

/// Everything the app keeps, in one value. Also the backup file format.
public struct Library: Codable, Equatable {
    public var version: Int
    public var courses: [Course]
    public var rounds: [Round]
    public var bag: [Club]
    public var settings: Settings

    public init(version: Int = 1, courses: [Course] = [], rounds: [Round] = [], bag: [Club] = Club.standardBag,
                settings: Settings = Settings()) {
        self.version = version
        self.courses = courses
        self.rounds = rounds
        self.bag = bag
        self.settings = settings
    }
}

/// Reads and writes the app's files. Each kind of data has its own JSON file so a problem with
/// one cannot take the others with it, and every write replaces the file in one step.
public final class Store {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func url(_ name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        do {
            return try Store.decoder().decode(type, from: data)
        } catch {
            // Keep the unreadable file rather than overwrite it with an empty one.
            let stamp = Int(Date().timeIntervalSince1970)
            try? FileManager.default.copyItem(at: url(name), to: url("\(name).unreadable-\(stamp)"))
            return nil
        }
    }

    @discardableResult
    func write<T: Encodable>(_ value: T, to name: String) -> Bool {
        do {
            let data = try Store.encoder().encode(value)
            try data.write(to: url(name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func load() -> Library {
        var library = Library()
        if let courses = read([Course].self, from: "courses.json") { library.courses = courses }
        if let rounds = read([Round].self, from: "rounds.json") { library.rounds = rounds }
        if let bag = read([Club].self, from: "bag.json"), !bag.isEmpty { library.bag = bag }
        if let settings = read(Settings.self, from: "settings.json") { library.settings = settings }
        return library
    }

    @discardableResult public func save(courses: [Course]) -> Bool { write(courses, to: "courses.json") }
    @discardableResult public func save(rounds: [Round]) -> Bool { write(rounds, to: "rounds.json") }
    @discardableResult public func save(bag: [Club]) -> Bool { write(bag, to: "bag.json") }
    @discardableResult public func save(settings: Settings) -> Bool { write(settings, to: "settings.json") }

    public func save(_ library: Library) {
        save(courses: library.courses)
        save(rounds: library.rounds)
        save(bag: library.bag)
        save(settings: library.settings)
    }

    /// One file holding everything, for keeping a copy outside the app.
    public static func backupData(_ library: Library) -> Data? {
        let encoder = Store.encoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var copy = library
        // The GHIN sign-in is not part of a backup.
        copy.settings.ghin = nil
        return try? encoder.encode(copy)
    }

    public static func library(fromBackup data: Data) -> Library? {
        try? Store.decoder().decode(Library.self, from: data)
    }
}
