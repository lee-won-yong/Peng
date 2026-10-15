import Foundation

let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
let path = CommandLine.arguments[2]
func statement(_ key: String, _ args: [Any] = []) -> [String: Any] {
  ["sql": fixture[key] as! String, "args": args]
}
func check(_ value: Bool, _ message: String) {
  if !value { fatalError(message) }
}
func expectFailure(_ action: () throws -> Void) {
  do { try action() } catch { return }
  fatalError("Expected failed transaction")
}
var db: LearningSQLite? = try LearningSQLite(path: path)
try db!.batch((fixture["schema"] as! [String]).map { ["sql": $0] })
let marker = ["sql": "INSERT INTO metadata(key,value) VALUES ('legacy_import_v1','1')"]
try db!.batch([
  statement("word", ["alley", "골목", "It's an alley.", 3, 2]),
  statement("day", ["2026-10-14"]),
  statement("link", ["2026-10-14", "alley"]), marker,
])
// Repeated registration must reuse the entry and preserve its score.
try db!.batch([
  statement("word", ["alley", "골목", "It's an alley.", 0, 0]),
  statement("day", ["2026-10-15"]),
  statement("link", ["2026-10-15", "alley"]),
  statement("link", ["2026-10-15", "alley"]),
])
check(try db!.execute("SELECT * FROM words").count == 1, "duplicate word")
check(try db!.execute("SELECT * FROM study_day_words").count == 2, "date memberships")
expectFailure {
  try db!.batch([statement("update", ["overwritten", "bad", 0, 0, "alley"]), marker])
}
var row = try db!.execute("SELECT * FROM words")[0]
check(row["meaning"] as! String == "골목", "import rollback must preserve Unicode data")
check(row["correct"] as! Int64 == 3, "legacy scores")
try db!.batch([
  statement("answer", ["alley", "2026-10-15", "2026-10-15T00:00:00Z", 1]),
  statement("score", [1, 0, "alley"]),
])
expectFailure {
  try db!.batch([
    statement("score", [1, 0, "alley"]),
    statement("answer", ["missing", "2026-10-15", "now", 0]),
  ])
}
try db!.batch([statement("enrich", ["골목", "A narrow alley.", "alley"])])
row = try db!.execute("SELECT * FROM words")[0]
check(row["correct"] as! Int64 == 4, "quiz rollback and count")
check(try db!.execute("SELECT * FROM quiz_attempts WHERE study_date='2026-10-15'").count == 1, "dated history")
expectFailure {
  try db!.execute("INSERT INTO words(word,meaning,example) VALUES ('ALLEY','duplicate','duplicate')")
}
db = nil
db = try LearningSQLite(path: path)
check(try db!.execute("SELECT * FROM words").count == 1, "restart persistence")
check(try db!.execute("PRAGMA integrity_check")[0]["integrity_check"] as! String == "ok", "integrity")
print("PASS: native SQLite persistence, Korean text, uniqueness, multi-date links, legacy scores, import rollback, dated quiz history, answer rollback, reopen, integrity.")

let reset = (fixture["reset"] as! [String]).map { ["sql": $0] }
expectFailure {
  try db!.batch(reset + [["sql": "INSERT INTO nonexistent VALUES (1)"]])
}
check(try db!.execute("SELECT * FROM words").count == 1, "failed reset preserves data")
try db!.batch(reset)
for table in ["words", "study_days", "study_day_words", "quiz_attempts"] {
  check(try db!.execute("SELECT * FROM \(table)").isEmpty, "reset clears \(table)")
}
db = nil
db = try LearningSQLite(path: path)
check(try db!.execute("SELECT * FROM metadata WHERE key='legacy_import_v1'").count == 1, "reset retains import marker")
check(try db!.execute("SELECT * FROM words").isEmpty, "reset persists across restart")
print("PASS: atomic reset, failed-reset rollback, empty restart, preserved import marker.")
