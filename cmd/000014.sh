set -e
dsync merge-a >/dev/null
grep -q "flutter_test" pubspec.yaml || printf '\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n' >> pubspec.yaml
flutter pub get 2>&1 | tail -1
mkdir -p test "$DS_ART"
cat > test/pinned_render_test.dart <<'EOF'
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LMClient/main.dart';

Future<void> loadFont(String family, List<String> paths) async {
  final FontLoader loader = FontLoader(family);
  for (final String p in paths) {
    if (File(p).existsSync()) loader.addFont(Future<ByteData>.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  testWidgets('pinned states', (WidgetTester tester) async {
    final String art = Platform.environment['DS_ART'] ?? '/tmp';
    await tester.runAsync(() async {
      await loadFont('DejaVu', <String>['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']);
      await loadFont('monospace', <String>['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf']);
    });
    final GlobalKey key = GlobalKey();
    final ThemeData base = buildTheme(Brightness.dark);
    await tester.binding.setSurfaceSize(const Size(390, 330));
    await tester.pumpWidget(MaterialApp(
      theme: base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'DejaVu')),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Container(
              color: const Color(0xFF000000),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: const <Widget>[
                TerminalPinnedPreview(state: 0),
                SizedBox(height: 24),
                TerminalPinnedPreview(state: 1),
                SizedBox(height: 24),
                TerminalPinnedPreview(state: 2),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() async {
      final RenderRepaintBoundary b = tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 2);
      final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$art/pinned.png').writeAsBytes(bd!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  });
}
EOF
flutter test test/pinned_render_test.dart 2>&1 | tail -12
ls "$DS_ART"
