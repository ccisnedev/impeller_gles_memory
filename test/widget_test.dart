import 'package:flutter_test/flutter_test.dart';
import 'package:impeller_gles_memory/main.dart';

void main() {
  test('each seed generates a different PNG', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final a = await generatePng(1);
    final b = await generatePng(2);
    expect(a, isNotEmpty);
    expect(a, isNot(equals(b)));
  });
}
