import Foundation
import SQLite3

// No Flutter dependency, so the real SQLite adapter can also be tested locally.
final class LearningSQLite {
  private var db: OpaquePointer?
  let path: String

  init(path: String) throws {
    self.path = path
    if sqlite3_open(path, &db) != SQLITE_OK {
      if db != nil { sqlite3_close(db) }
      db = nil
      throw NSError(domain: "PengSQLite", code: 1)
    }
    sqlite3_busy_timeout(db, 5000)
    _ = try execute("PRAGMA foreign_keys = ON")
  }

  deinit { sqlite3_close(db) }

  private func error() -> Error {
    NSError(domain: "PengSQLite", code: Int(sqlite3_errcode(db)),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
  }

  @discardableResult
  func execute(_ sql: String, args: [Any] = []) throws -> [[String: Any]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_bind_parameter_count(statement) == args.count else {
      throw NSError(domain: "PengSQLite", code: 2)
    }
    for (offset, value) in args.enumerated() {
      let index = Int32(offset + 1)
      let status: Int32
      if value is NSNull {
        status = sqlite3_bind_null(statement, index)
      } else if let number = value as? NSNumber {
        status = sqlite3_bind_int64(statement, index, number.int64Value)
      } else if let text = value as? String {
        status = sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      } else {
        throw NSError(domain: "PengSQLite", code: 3)
      }
      guard status == SQLITE_OK else { throw error() }
    }
    var rows = [[String: Any]]()
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return rows }
      guard status == SQLITE_ROW else { throw error() }
      var row = [String: Any]()
      for column in 0..<sqlite3_column_count(statement) {
        let name = String(cString: sqlite3_column_name(statement, column))
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, column)
        case SQLITE_NULL: row[name] = NSNull()
        default: row[name] = String(cString: sqlite3_column_text(statement, column))
        }
      }
      rows.append(row)
    }
  }

  func batch(_ statements: [[String: Any]]) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      for statement in statements {
        guard let sql = statement["sql"] as? String else { throw NSError(domain: "PengSQLite", code: 4) }
        try execute(sql, args: statement["args"] as? [Any] ?? [])
      }
      try execute("COMMIT")
    } catch {
      _ = try? execute("ROLLBACK")
      throw error
    }
  }
}
