"""Rebuild the preview DB with the same schema and seed used by the mobile app."""
import datetime
import json
import re
import sqlite3
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = json.loads((ROOT / 'assets/data/il_seong_interview.json').read_text())
schema_source = (ROOT / 'lib/learning_database.dart').read_text()
schema = [sql for sql in re.findall(r"'([^'\n]*)'", schema_source) if sql.startswith('CREATE TABLE')]
output = ROOT / 'data/peng.sqlite'
output.parent.mkdir(exist_ok=True)
# This is an explicitly generated preview, never a connected device database.
with tempfile.NamedTemporaryFile(dir=output.parent, suffix='.sqlite', delete=False) as file:
    temporary = Path(file.name)
try:
    db = sqlite3.connect(temporary)
    try:
        with db:
            db.execute('PRAGMA foreign_keys=ON')
            for statement in schema:
                db.execute(statement)
            date = datetime.date.today().isoformat()
            db.execute('INSERT INTO study_days VALUES (?)', (date,))
            for word in source['words']:
                db.execute('INSERT INTO words VALUES (?,?,?,?,?)',
                           (word['word'], word['meaning'], word['example'], 0, 0))
                db.execute('INSERT INTO study_day_words VALUES (?,?)', (date, word['word']))
            db.execute("INSERT INTO metadata VALUES ('legacy_import_v1','1')")
            assert db.execute('SELECT COUNT(*) FROM words').fetchone()[0] == 14
            assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    finally:
        db.close()
    temporary.replace(output)
finally:
    temporary.unlink(missing_ok=True)
print(f'14 words saved to preview database: {output}')
