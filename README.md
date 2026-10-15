# Peng

Peng is a private Flutter MVP for turning a child's English book pages into a small vocabulary trainer.

## Current MVP

- Pick a page photo from camera or gallery.
- Run on-device English OCR with Google ML Kit.
- Extract likely English vocabulary words.
- Save words locally on the device.
- Read words aloud with TTS.
- Practice with a simple multiple-choice quiz.

## Setup

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
