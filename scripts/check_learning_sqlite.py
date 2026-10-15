"""Run the production Swift SQLite adapter against the Dart repository's SQL."""
import json
import re
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'lib/learning_database.dart').read_text()
strings = re.findall(r"'([^'\n]*)'", source)
schema = [sql for sql in strings if sql.startswith('CREATE TABLE')]
def sql(prefix):
    return next(value for value in strings if value.startswith(prefix))
fixture = {
    'schema': schema,
    'reset': [value for value in strings if value.startswith('DELETE FROM')],
    'word': sql('INSERT OR IGNORE INTO words'),
    'update': sql('UPDATE words SET meaning'),
    'enrich': sql('UPDATE words SET meaning=?,example=? WHERE'),
    'day': sql('INSERT OR IGNORE INTO study_days'),
    'link': sql('INSERT OR IGNORE INTO study_day_words'),
    'answer': sql('INSERT INTO quiz_attempts'),
    'score': sql('UPDATE words SET correct=correct+'),
}
with tempfile.TemporaryDirectory(prefix='peng-sqlite-') as directory:
    folder = Path(directory)
    (folder / 'fixture.json').write_text(json.dumps(fixture))
    subprocess.run(['swiftc', '-module-cache-path', str(folder / 'modules'),
                    str(root / 'ios/Runner/LearningSQLite.swift'),
                    str(root / 'test/native_sqlite/main.swift'), '-o', str(folder / 'check')], check=True)
    subprocess.run([str(folder / 'check'), str(folder / 'fixture.json'), str(folder / 'peng.sqlite')], check=True)
