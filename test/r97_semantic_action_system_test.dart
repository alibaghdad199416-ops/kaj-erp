import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/design_system/kaj_component_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_universal_components.dart';

void main() {
  testWidgets('R97 semantic action tones use canonical button primitives', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: <Widget>[
              KajActionButton.primary(
                key: const Key('primary'),
                label: 'Save',
                icon: Icons.save_outlined,
                onPressed: () => taps++,
              ),
              KajActionButton.secondary(
                label: 'Cancel',
                onPressed: () {},
              ),
              KajActionButton.approve(
                label: 'Approve',
                onPressed: () {},
              ),
              KajActionButton.danger(
                label: 'Delete',
                onPressed: () {},
              ),
              KajActionButton.neutral(
                label: 'Details',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(FilledButton), findsNWidgets(3));
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('primary'))).height,
      greaterThanOrEqualTo(KajComponentTokens.controlHeight),
    );

    await tester.tap(find.byKey(const Key('primary')));
    expect(taps, 1);
  });

  testWidgets('busy action is disabled and uses compact control height', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KajActionButton.primary(
            key: const Key('busy'),
            label: 'Saving',
            compact: true,
            busy: true,
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    final filled = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(filled.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('busy'))).height,
      greaterThanOrEqualTo(KajComponentTokens.compactControlHeight),
    );
    await tester.tap(find.byKey(const Key('busy')));
    expect(taps, 0);
  });
}
