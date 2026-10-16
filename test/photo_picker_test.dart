import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:peng/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/database_channel.dart';

class FakeImagePicker extends ImagePicker {
  final sources = <ImageSource>[];
  PlatformException? error;
  bool? fullMetadata;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    sources.add(source);
    fullMetadata = requestFullMetadata;
    if (error != null) throw error!;
    return null;
  }
}

void main() {
  setUp(() {
    rootBundle.evict('assets/data/il_seong_interview.json');
    DatabaseChannelFake().install();
    SharedPreferences.setMockInitialValues({
      'peng_seed_ktv_il_seong_2020_v1': true,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          (_) async => 1,
        );
  });

  Future<void> openScan(WidgetTester tester, FakeImagePicker picker) async {
    await tester.pumpWidget(MaterialApp(home: HomeScreen(imagePicker: picker)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'camera and album open without an API key and recover on cancel',
    (tester) async {
      final picker = FakeImagePicker();
      await openScan(tester, picker);
      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('앨범'));
      await tester.pumpAndSettle();
      expect(picker.sources, [ImageSource.camera, ImageSource.gallery]);
      expect(picker.fullMetadata, isFalse);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied permission explains recovery and allows retry', (
    tester,
  ) async {
    final picker = FakeImagePicker()
      ..error = PlatformException(code: 'camera_access_denied');
    await openScan(tester, picker);
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('카메라 접근을 허용'), findsOneWidget);
    picker.error = null;
    await tester.tap(find.text('앨범'));
    await tester.pumpAndSettle();
    expect(picker.sources, [ImageSource.camera, ImageSource.gallery]);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
