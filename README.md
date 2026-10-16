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

## AR learning level

Settings includes an AR target range (0.5–12.0 in 0.5 increments, default 3.0–5.0).
The selection is saved locally as `peng_ar_level_v1` and is applied to new API
vocabulary selection and example generation. Higher ranges prioritize academic,
abstract, nuanced vocabulary and more complex contextual examples. Phrasal verbs
of up to three words are supported. If a text is too easy, the API may return
fewer words or none; raw tokens are not added after API selection or failure.
Re-extracting a previously saved word refreshes its meaning and example at the
selected level while preserving scores and date links. Existing saved vocabulary
is not automatically deleted or regenerated when the level changes.

AR is a reading-difficulty target here, not a certified score for generated
words or sentences. Official ATOS scores measure text readability, including
sentence length, word length and word difficulty:
[Renaissance: Book, Interest, and Reading Levels](https://arhelp.renaissance.com/hc/en-us/articles/12630557859227-Levels-Book-Interest-and-Reading).

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
API keys are read only from the build configuration; the settings UI contains
parent phone and learning data controls. Legacy saved API keys are ignored.

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

### Local API key

Set `OPENAI_API_KEY` in the project root's `env.local.json`:

```json
{
  "OPENAI_API_KEY": "your-api-key"
}
```

`env.local.json` is excluded from Git. On a new checkout, copy
`env.example.json` to `env.local.json` first. Pass the file when running or building:

```sh
flutter run --dart-define-from-file=env.local.json
flutter run --release --dart-define-from-file=env.local.json
flutter build ios --release --dart-define-from-file=env.local.json
flutter build apk --release --dart-define-from-file=env.local.json
```

The app uses only `OPENAI_API_KEY` from the build configuration. API keys cannot
be entered in the app settings. Changes to the file require stopping and
rebuilding the app.
The key is included in the built app; ignoring the file prevents committing it
to Git but does not protect it from extraction from distributed apps.

This repository currently contains the Flutter source files. If platform folders are missing, generate them once:

```sh
flutter create --platforms=ios,android .
flutter pub get
flutter run
```

For iPhone testing without a paid developer account, open the generated iOS project in Xcode, sign with your Apple ID, and run on the connected device. Free signing may require reinstalling periodically.

## iOS Notes

iOS plugins use CocoaPods (`flutter.config.enable-swift-package-manager: false`)
so plugin frameworks and resource bundles are built by the same dependency manager.

After `flutter create`, add these usage descriptions in `ios/Runner/Info.plist` if they are not present:

- `NSCameraUsageDescription`: Used to scan English book pages.
- `NSPhotoLibraryUsageDescription`: Used to choose book page photos.

## Android Notes

Recent Android versions generally work with the generated permissions from `image_picker`, but camera/gallery behavior should still be tested on a real device.
