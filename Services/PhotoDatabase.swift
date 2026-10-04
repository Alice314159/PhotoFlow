import Foundation
import SQLite3

final class PhotoDatabase: @unchecked Sendable {
    static let shared = PhotoDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.photoflow.sqlite")

    private init() {
        open()
        migrate()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func annotations(for paths: [String]) -> [String: PhotoItem] {
        guard !paths.isEmpty else { return [:] }
        return queue.sync {
            var result: [String: PhotoItem] = [:]
            for chunk in paths.chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let sql = """
                SELECT file_path, rating, color_label, pick_status, shutter_speed, aperture, iso,
                       focal_length, camera, camera_make, lens, width, height, created_date, file_mtime
                FROM photos
                WHERE file_path IN (\(placeholders));
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(statement) }

                for (index, path) in chunk.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), path, -1, SQLITE_TRANSIENT)
                }

                while sqlite3_step(statement) == SQLITE_ROW {
                    let item = photo(from: statement)
                    result[item.filePath] = item
                }
            }
            return result
        }
    }

    func save(_ photo: PhotoItem) {
        queue.sync {
            let sql = """
            INSERT INTO photos (
                file_path, rating, color_label, pick_status, shutter_speed, aperture, iso,
                focal_length, camera, camera_make, lens, width, height, created_date, file_mtime, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
                rating = excluded.rating,
                color_label = excluded.color_label,
                pick_status = excluded.pick_status,
                shutter_speed = excluded.shutter_speed,
                aperture = excluded.aperture,
                iso = excluded.iso,
                focal_length = excluded.focal_length,
                camera = excluded.camera,
                camera_make = excluded.camera_make,
                lens = excluded.lens,
                width = excluded.width,
                height = excluded.height,
                created_date = excluded.created_date,
                file_mtime = excluded.file_mtime,
                updated_at = excluded.updated_at;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            bind(photo, to: statement)
            sqlite3_step(statement)
        }
    }

    func updatePath(from oldPath: String, to newPath: String) {
        queue.sync {
            let sql = "UPDATE photos SET file_path = ?, updated_at = ? WHERE file_path = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, newPath, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, oldPath, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)

            for table in ["photo_analysis", "collection_items", "photo_location"] {
                var update: OpaquePointer?
                guard sqlite3_prepare_v2(db, "UPDATE OR IGNORE \(table) SET file_path = ? WHERE file_path = ?;", -1, &update, nil) == SQLITE_OK else {
                    continue
                }
                sqlite3_bind_text(update, 1, newPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(update, 2, oldPath, -1, SQLITE_TRANSIENT)
                sqlite3_step(update)
                sqlite3_finalize(update)
            }
        }
    }

    func saveMany(_ photos: [PhotoItem]) {
        queue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for photo in photos {
                saveUnlocked(photo)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    private func saveUnlocked(_ photo: PhotoItem) {
        let sql = """
        INSERT INTO photos (
            file_path, rating, color_label, pick_status, shutter_speed, aperture, iso,
            focal_length, camera, camera_make, lens, width, height, created_date, file_mtime, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(file_path) DO UPDATE SET
            rating = excluded.rating,
            color_label = excluded.color_label,
            pick_status = excluded.pick_status,
            shutter_speed = excluded.shutter_speed,
            aperture = excluded.aperture,
            iso = excluded.iso,
            focal_length = excluded.focal_length,
            camera = excluded.camera,
            camera_make = excluded.camera_make,
            lens = excluded.lens,
            width = excluded.width,
            height = excluded.height,
            created_date = excluded.created_date,
            file_mtime = excluded.file_mtime,
            updated_at = excluded.updated_at;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(photo, to: statement)
        sqlite3_step(statement)
    }

    private func open() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PhotoFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("photoflow.sqlite")

        if sqlite3_open(url.path, &db) != SQLITE_OK {
            sqlite3_close(db)
            db = nil
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys=ON;", nil, nil, nil)
    }

    private func migrate() {
        let sql = """
        CREATE TABLE IF NOT EXISTS photos (
            file_path TEXT PRIMARY KEY NOT NULL,
            rating INTEGER NOT NULL DEFAULT 0,
            color_label TEXT NOT NULL DEFAULT 'none',
            pick_status TEXT NOT NULL DEFAULT 'none',
            shutter_speed REAL,
            aperture REAL,
            iso INTEGER,
            focal_length REAL,
            camera TEXT,
            camera_make TEXT,
            lens TEXT,
            width INTEGER,
            height INTEGER,
            created_date REAL,
            file_mtime REAL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_photos_rating ON photos(rating);
        CREATE INDEX IF NOT EXISTS idx_photos_color ON photos(color_label);
        CREATE INDEX IF NOT EXISTS idx_photos_pick ON photos(pick_status);

        CREATE TABLE IF NOT EXISTS photo_analysis (
            file_path TEXT PRIMARY KEY NOT NULL,
            categories TEXT NOT NULL DEFAULT '',
            labels TEXT NOT NULL DEFAULT '',
            face_count INTEGER NOT NULL DEFAULT 0,
            version INTEGER NOT NULL DEFAULT 0,
            manual INTEGER NOT NULL DEFAULT 0,
            analyzed_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS collections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS collection_items (
            collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
            file_path TEXT NOT NULL,
            added_at REAL NOT NULL,
            PRIMARY KEY (collection_id, file_path)
        );
        CREATE INDEX IF NOT EXISTS idx_collection_items_path ON collection_items(file_path);

        CREATE TABLE IF NOT EXISTS photo_location (
            file_path TEXT PRIMARY KEY NOT NULL,
            latitude REAL,
            longitude REAL,
            place_name TEXT,
            place_text TEXT,
            manual INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS place_cache (
            cell TEXT PRIMARY KEY NOT NULL,
            place_name TEXT NOT NULL,
            place_text TEXT NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Locations

    struct StoredLocation: Sendable {
        var latitude: Double? = nil
        var longitude: Double? = nil
        var placeName: String? = nil
        var placeText: String? = nil
    }

    func locations(for paths: [String]) -> [String: StoredLocation] {
        guard !paths.isEmpty else { return [:] }
        return queue.sync {
            var result: [String: StoredLocation] = [:]
            for chunk in paths.chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let sql = "SELECT file_path, latitude, longitude, place_name, place_text FROM photo_location WHERE file_path IN (\(placeholders));"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(statement) }
                for (index, path) in chunk.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), path, -1, SQLITE_TRANSIENT)
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let path = string(statement, 0) else { continue }
                    result[path] = StoredLocation(
                        latitude: double(statement, 1),
                        longitude: double(statement, 2),
                        placeName: string(statement, 3),
                        placeText: string(statement, 4)
                    )
                }
            }
            return result
        }
    }

    /// Upserts rows; nil coordinates mean "checked, no GPS".
    func saveLocations(_ items: [(path: String, location: StoredLocation, manual: Bool)]) {
        guard !items.isEmpty else { return }
        queue.sync {
            let sql = """
            INSERT INTO photo_location (file_path, latitude, longitude, place_name, place_text, manual, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
                latitude = excluded.latitude,
                longitude = excluded.longitude,
                place_name = excluded.place_name,
                place_text = excluded.place_text,
                manual = excluded.manual,
                updated_at = excluded.updated_at;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            let now = Date().timeIntervalSince1970
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for item in items {
                sqlite3_reset(statement)
                sqlite3_bind_text(statement, 1, item.path, -1, SQLITE_TRANSIENT)
                bindOptional(item.location.latitude, at: 2, statement)
                bindOptional(item.location.longitude, at: 3, statement)
                bindOptional(item.location.placeName, at: 4, statement)
                bindOptional(item.location.placeText, at: 5, statement)
                sqlite3_bind_int(statement, 6, item.manual ? 1 : 0)
                sqlite3_bind_double(statement, 7, now)
                sqlite3_step(statement)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    func cachedPlace(cell: String) -> (name: String, text: String)? {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT place_name, place_text FROM place_cache WHERE cell = ?;", -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, cell, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let name = string(statement, 0), let text = string(statement, 1) else { return nil }
            return (name, text)
        }
    }

    func cachePlace(cell: String, name: String, text: String) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO place_cache (cell, place_name, place_text) VALUES (?, ?, ?);", -1, &statement, nil) == SQLITE_OK else {
                return
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, cell, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, text, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
        }
    }

    // MARK: - Content analysis

    struct StoredAnalysis: Sendable {
        var categories: Set<PhotoCategory>
        var labels: [String]
        var version: Int
        var manual: Bool
    }

    func analyses(for paths: [String]) -> [String: StoredAnalysis] {
        guard !paths.isEmpty else { return [:] }
        return queue.sync {
            var result: [String: StoredAnalysis] = [:]
            for chunk in paths.chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let sql = "SELECT file_path, categories, labels, version, manual FROM photo_analysis WHERE file_path IN (\(placeholders));"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(statement) }
                for (index, path) in chunk.enumerated() {
                    sqlite3_bind_text(statement, Int32(index + 1), path, -1, SQLITE_TRANSIENT)
                }
                while sqlite3_step(statement) == SQLITE_ROW {
                    guard let path = string(statement, 0) else { continue }
                    let labels = (string(statement, 2) ?? "").split(separator: ",").map(String.init)
                    result[path] = StoredAnalysis(
                        categories: PhotoCategory.decode(string(statement, 1)),
                        labels: labels,
                        version: Int(sqlite3_column_int(statement, 3)),
                        manual: sqlite3_column_int(statement, 4) != 0
                    )
                }
            }
            return result
        }
    }

    func saveAnalyses(_ items: [(path: String, categories: Set<PhotoCategory>, labels: [String], faceCount: Int, version: Int, manual: Bool)]) {
        guard !items.isEmpty else { return }
        queue.sync {
            let sql = """
            INSERT INTO photo_analysis (file_path, categories, labels, face_count, version, manual, analyzed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
                categories = excluded.categories,
                labels = excluded.labels,
                face_count = excluded.face_count,
                version = excluded.version,
                manual = excluded.manual,
                analyzed_at = excluded.analyzed_at;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            let now = Date().timeIntervalSince1970
            for item in items {
                sqlite3_reset(statement)
                sqlite3_bind_text(statement, 1, item.path, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 2, PhotoCategory.encode(item.categories), -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(statement, 3, item.labels.joined(separator: ","), -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 4, Int32(item.faceCount))
                sqlite3_bind_int(statement, 5, Int32(item.version))
                sqlite3_bind_int(statement, 6, item.manual ? 1 : 0)
                sqlite3_bind_double(statement, 7, now)
                sqlite3_step(statement)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    // MARK: - Collections

    func loadCollections() -> [PhotoCollection] {
        queue.sync {
            var collections: [Int64: PhotoCollection] = [:]
            var order: [Int64] = []
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT id, name, created_at FROM collections ORDER BY name COLLATE NOCASE;", -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = sqlite3_column_int64(statement, 0)
                    collections[id] = PhotoCollection(
                        id: id,
                        name: string(statement, 1) ?? "Untitled",
                        paths: [],
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    )
                    order.append(id)
                }
            }
            sqlite3_finalize(statement)

            statement = nil
            if sqlite3_prepare_v2(db, "SELECT collection_id, file_path FROM collection_items;", -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    let id = sqlite3_column_int64(statement, 0)
                    if let path = string(statement, 1) {
                        collections[id]?.paths.insert(path)
                    }
                }
            }
            sqlite3_finalize(statement)
            return order.compactMap { collections[$0] }
        }
    }

    func createCollection(named name: String) -> Int64? {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO collections (name, created_at) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK else {
                return nil
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func renameCollection(_ id: Int64, to name: String) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE collections SET name = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 2, id)
            sqlite3_step(statement)
        }
    }

    func deleteCollection(_ id: Int64) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM collections WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            sqlite3_step(statement)
        }
    }

    func addToCollection(_ id: Int64, paths: [String]) {
        editCollection(id, paths: paths, sql: "INSERT OR IGNORE INTO collection_items (collection_id, file_path, added_at) VALUES (?, ?, ?);")
    }

    func removeFromCollection(_ id: Int64, paths: [String]) {
        editCollection(id, paths: paths, sql: "DELETE FROM collection_items WHERE collection_id = ? AND file_path = ?;")
    }

    private func editCollection(_ id: Int64, paths: [String], sql: String) {
        guard !paths.isEmpty else { return }
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            let now = Date().timeIntervalSince1970
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for path in paths {
                sqlite3_reset(statement)
                sqlite3_bind_int64(statement, 1, id)
                sqlite3_bind_text(statement, 2, path, -1, SQLITE_TRANSIENT)
                if sqlite3_bind_parameter_count(statement) >= 3 {
                    sqlite3_bind_double(statement, 3, now)
                }
                sqlite3_step(statement)
            }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    private func bind(_ photo: PhotoItem, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, 1, photo.filePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(photo.rating))
        sqlite3_bind_text(statement, 3, photo.colorLabel.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, photo.pickStatus.rawValue, -1, SQLITE_TRANSIENT)
        bindOptional(photo.shutterSpeed, at: 5, statement)
        bindOptional(photo.aperture, at: 6, statement)
        if let iso = photo.iso {
            sqlite3_bind_int(statement, 7, Int32(iso))
        } else {
            sqlite3_bind_null(statement, 7)
        }
        bindOptional(photo.focalLength, at: 8, statement)
        bindOptional(photo.camera, at: 9, statement)
        bindOptional(photo.cameraMake, at: 10, statement)
        bindOptional(photo.lens, at: 11, statement)
        if let width = photo.width { sqlite3_bind_int(statement, 12, Int32(width)) } else { sqlite3_bind_null(statement, 12) }
        if let height = photo.height { sqlite3_bind_int(statement, 13, Int32(height)) } else { sqlite3_bind_null(statement, 13) }
        bindOptional(photo.createdDate?.timeIntervalSince1970, at: 14, statement)
        bindOptional(photo.fileModificationDate?.timeIntervalSince1970, at: 15, statement)
        sqlite3_bind_double(statement, 16, Date().timeIntervalSince1970)
    }

    private func bindOptional(_ value: Double?, at index: Int32, _ statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptional(_ value: String?, at index: Int32, _ statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func photo(from statement: OpaquePointer?) -> PhotoItem {
        var item = PhotoItem(filePath: string(statement, 0) ?? "")
        item.rating = Int(sqlite3_column_int(statement, 1))
        item.colorLabel = ColorLabel(rawValue: string(statement, 2) ?? "none") ?? .none
        item.pickStatus = PickStatus(rawValue: string(statement, 3) ?? "none") ?? .none
        item.shutterSpeed = double(statement, 4)
        item.aperture = double(statement, 5)
        item.iso = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6))
        item.focalLength = double(statement, 7)
        item.camera = string(statement, 8)
        item.cameraMake = string(statement, 9)
        item.lens = string(statement, 10)
        item.width = sqlite3_column_type(statement, 11) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 11))
        item.height = sqlite3_column_type(statement, 12) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 12))
        if let created = double(statement, 13) { item.createdDate = Date(timeIntervalSince1970: created) }
        if let mtime = double(statement, 14) { item.fileModificationDate = Date(timeIntervalSince1970: mtime) }
        return item
    }

    private func string(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func double(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
