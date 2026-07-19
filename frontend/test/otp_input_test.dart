import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civicroute/features/citizen/auth/presentation/widgets/otp_input.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders one box per digit', (tester) async {
    await tester.pumpWidget(
      _host(OtpInput(onChanged: (_) {})),
    );
    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('typing advances focus and reports the concatenated value',
      (tester) async {
    final values = <String>[];
    String? completed;

    await tester.pumpWidget(
      _host(OtpInput(
        onChanged: values.add,
        onCompleted: (v) => completed = v,
      )),
    );

    final boxes = find.byType(TextField);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(boxes.at(i), '${i + 1}');
      await tester.pump();
    }

    expect(values.last, '123456');
    expect(completed, '123456');
  });
}
