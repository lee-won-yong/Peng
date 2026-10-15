# Peng

Peng is a private Flutter MVP for turning a child's English book pages into a small vocabulary trainer.

## Current MVP

- Pick a page photo from camera or gallery.
- Extract photo text with the configured OpenAI API.
- Automatically prepare English vocabulary, Korean meanings, and English examples.
- Save words locally on the device.
- Read words aloud with TTS.
- Select a date card in Words or Quiz, then review words or answer questions.
- Start on the quiz date list; vocabulary is read-only and examples appear after answering.

## Interview learning data

`assets/data/il_seong_interview.json` contains the user-provided KTV interview
excerpt, a Korean translation, and 14 vocabulary entries with meanings and
source-sentence examples. Inflected words are normalized; proper names are
excluded. The source attribution is user-provided and has not been independently
verified.

The app imports this vocabulary once, preserving existing entries and quiz
scores. Deleted seed entries are not re-added on later launches.
Missing meanings/examples for existing seed words are filled automatically.

New text uses the configured API key and connection to generate complete entries;
failed requests do not register blank vocabulary. The bundled interview works
without an API key. API responses follow the
[Structured Outputs schema](https://developers.openai.com/api/docs/guides/structured-outputs).
Words are unique after trimming and lowercasing. Repeated registration preserves
quiz scores and links the existing word to the current local calendar date.
Words can belong to multiple dates without duplicating the entry. Older entries
without dates are assigned the local date on first migration. Quiz scores belong
to the word and are shared across its dates. Each date needs four complete words
for a quiz. Dates are stored with the words and restored on launch.

## SQLite storage

Learning data uses the built-in SQLite engine on iOS and Android through the
`peng/database` channel. No additional package is required. Tables are `words`,
`study_days`, `study_day_words`, `quiz_attempts`, and `metadata`. Words have a
unique, lowercase trimmed key; date links have a composite primary key. New quiz
answers atomically append dated history and update cumulative scores. Historical
aggregate scores are preserved without inventing dates for old attempts.

At first launch, existing `peng_words_v1` data and seed state are imported in one
transaction. The database import marker prevents replay. The app reads back and
checks every word, meaning, example, score, and date before removing the two old
learning preference keys. Failed imports retain the source preferences.
`peng_openai_key_v1` remains in SharedPreferences with the existing settings UI.

Live database locations:
- iOS: the app container's `Library/Application Support/peng.sqlite`.
- Android: the app container's `databases/peng.sqlite` (Android Studio Device Explorer).

`LearningDatabase.path()` returns the exact device path. Export the app container
while the app is stopped and open the database in DB Browser for SQLite.
The repository's `data/peng.sqlite` is a generated preview with the same schema,
not the running phone's database. Rebuild it from the bundled interview with
`python3 scripts/build_interview_db.py`; generated databases are ignored by Git.

Verification:
- `python3 scripts/check_learning_sqlite.py` compiles the production Swift adapter
  and tests real SQLite persistence, constraints, migration rollback and quiz history.
- `flutter test` covers UI migration, unchanged API keys, date navigation and failures.

Native storage API references:
[SQLite](https://www.sqlite.org/c3ref/stmt.html) and
[Android SQLiteDatabase](https://developer.android.com/reference/android/database/sqlite/SQLiteDatabase).

## Flutter setup

This repository currently contains the Flutter source files. If platform folders are missing, generate them once:

```sh
flutter create --platforms=ios,android .
flutter pub get
flutter run
```

For iPhone testing without a paid developer account, open the generated iOS project in Xcode, sign with your Apple ID, and run on the connected device. Free signing may require reinstalling periodically.

## iOS Notes

After `flutter create`, add these usage descriptions in `ios/Runner/Info.plist` if they are not present:

- `NSCameraUsageDescription`: Used to scan English book pages.
- `NSPhotoLibraryUsageDescription`: Used to choose book page photos.

## Android Notes

Recent Android versions generally work with the generated permissions from `image_picker`, but camera/gallery behavior should still be tested on a real device.
