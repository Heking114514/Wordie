import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('test harness boots', (tester) async {
    expect(tester.binding, isNotNull);
  });
}
