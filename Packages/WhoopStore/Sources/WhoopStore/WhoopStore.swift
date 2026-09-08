import Foundation
import GRDB
import WhoopProtocol

/// OpenWhoop persistence library — decoded streams are durable; raw frames are a
/// transient, compressed, prunable outbox. Built on GRDB/SQLite.
public enum WhoopStoreInfo {
    /// Bumped whenever the migrator gains a new migration.
    public static let schemaVersion = 9
}

/// SQLite page-cache / mmap budget. The Mac values speed multi-thousand-row
/// imports; the same mmap (256 MB) **per open handle** is enough to jetsam an
/// iPhone, and the app opens two handles (BLE collector + Repository).
public enum SQLiteTuning: Sendable {
    /// `PRAGMA cache_size` in kibibytes (negative form).
    public static var pageCacheKib: Int {
        #if os(iOS)
        4_000
        #else
        16_000
        #endif
    }

    /// `PRAGMA mmap_size` in bytes. `0` disables mmap on iOS.
    public static var mmapBytes: Int {
        #if os(iOS)
        0
        #else
        268_435_456
        #endif
    }

    public static var tempStoreSQL: String {
        #if os(iOS)
        "FILE"
        #else
        "MEMORY"
        #endif
    }
}

/// WhoopStore is an `actor`: its public API is `async`, and all GRDB work runs on the
/// actor's serial executor rather than the caller's (the main actor). DatabaseQueue calls
/// are synchronous-blocking; the actor moves them off the main thread (it does not make them
/// non-blocking). That is the intended off-main win — DatabaseQueue kept, not DatabasePool.
public actor WhoopStore {
    let dbQueue: DatabaseQueue

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try WhoopStore.makeMigrator().migrate(dbQueue)
    }

    /// Open (creating if needed) a database at `path` and run migrations.
    /// Enables WAL journal mode and a 5-second busy timeout so two handles to the same
    /// file (BLEManager + MetricsRepository) don't deadlock on write contention.
    public init(path: String) async throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Bulk-write/read tuning. NORMAL is the durable, recommended pairing with WAL (only an
            // OS crash/power loss can lose the last transaction — acceptable here). Page cache /
            // mmap / temp store are platform-capped: see SQLiteTuning. Two DatabaseQueue handles
            // each used to mmap 256 MB, which iOS jetsam treats as real memory.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA cache_size = -\(SQLiteTuning.pageCacheKib)")
            try db.execute(sql: "PRAGMA mmap_size = \(SQLiteTuning.mmapBytes)")
            try db.execute(sql: "PRAGMA temp_store = \(SQLiteTuning.tempStoreSQL)")
        }
        config.busyMode = .timeout(5)
        try self.init(dbQueue: try DatabaseQueue(path: path, configuration: config))
    }

    /// An in-memory store (migrations applied). For tests.
    public static func inMemory() async throws -> WhoopStore {
        try WhoopStore(dbQueue: try DatabaseQueue())
    }

    // MARK: - Synchronous GRDB helpers
    // GRDB 6 marks its sync read/write overloads @_disfavoredOverload so that in an async
    // context Swift would otherwise pick the async overloads. These thin wrappers are
    // regular (non-async) functions, so overload resolution always selects the synchronous
    // GRDB API — which then blocks on the actor's serial executor (off main thread).

    @inline(__always)
    func syncRead<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    @inline(__always)
    func syncWrite<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    // MARK: - Maintenance

    /// Wipe imported and on-device computed scores so a WHOOP / Apple Health export can be
    /// reimported cleanly. Raw BLE streams (`hrSample`, R-R, type-47 biometrics, events,
    /// battery, raw outbox) stay put — those are the strap's own samples and will refill
    /// the computed `*-noop` caches on the next IntelligenceEngine pass.
    public func clearImportedHistory() async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM dailyMetric")
            try db.execute(sql: "DELETE FROM sleepSession")
            try db.execute(sql: "DELETE FROM metricSeries")
            try db.execute(sql: "DELETE FROM journal")
            try db.execute(sql: "DELETE FROM workout")
            try db.execute(sql: "DELETE FROM appleDaily")
        }
    }

    /// Fully checkpoint the WAL into the main database file and truncate the -wal file.
    /// Used before a file-level backup so the single `whoop.sqlite` carries all committed data
    /// (the -wal/-shm siblings can then be ignored). Runs outside a transaction — `wal_checkpoint`
    /// must. Best-effort: throws on a hard SQLite error so callers can fall back to a plain copy.
    public func checkpointWAL() async throws {
        try checkpointWALImpl()
    }

    /// Non-async so GRDB's synchronous `writeWithoutTransaction` overload is chosen (mirrors the
    /// syncRead/syncWrite pattern). Runs on the actor's executor, off the main thread.
    private func checkpointWALImpl() throws {
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    // MARK: - Introspection (used by tests)

    public func tableNames() async throws -> Set<String> {
        try syncRead { db in
            try Set(String.fetchAll(db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    public func primaryKeyColumns(_ table: String) async throws -> [String] {
        try syncRead { db in
            try db.primaryKey(table).columns
        }
    }

    public func columnNamesForTest(table: String) async throws -> [String] {
        try syncRead { db in
            try db.columns(in: table).map(\.name)
        }
    }

    public func indexNamesForTest(table: String) async throws -> Set<String> {
        try syncRead { db in
            try Set(db.indexes(on: table).map(\.name))
        }
    }

    /// Current `PRAGMA mmap_size` (bytes). Used by tests to lock the iOS jetsam cap.
    public func mmapSize() async throws -> Int64 {
        try syncRead { db in
            try Int64.fetchOne(db, sql: "PRAGMA mmap_size") ?? 0
        }
    }
}
