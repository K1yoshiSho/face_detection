import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:face_camera/face_camera.dart';

void main() {
  const MethodChannel channel = MethodChannel('face_camera');

  TestWidgetsFlutterBinding tester = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    tester.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    tester.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getCameras', () async {
    expect(FaceCamera.cameras, []);
  });
}
