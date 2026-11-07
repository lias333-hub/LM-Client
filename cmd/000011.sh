set -e
dsync merge-a >/dev/null
grep -q "flutter_test" pubspec.yaml || sed -i 's/^dev_dependencies:/dev_dependencies:\n  flutter_test:\n    sdk: flutter/' pubspec.yaml
grep -n "dev_dependencies" -A4 pubspec.yaml | head -8
flutter pub get 2>&1 | tail -2
mkdir -p test
cat > test/usage_render_test.dart <<'EOF'
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
  testWidgets('usage table both directions', (WidgetTester tester) async {
    final String art = Platform.environment['DS_ART'] ?? '/tmp';
    await tester.runAsync(() async {
      final String root = Platform.environment['FLUTTER_ROOT'] ?? '';
      await loadFont('DejaVu', <String>['/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf']);
      await loadFont('monospace', <String>['/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf']);
      await loadFont('Roboto', <String>['$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf']);
    });
    final GlobalKey key = GlobalKey();
    final ThemeData base = buildTheme(Brightness.dark);
    const RunUsage mine = RunUsage(input: 26900, cached: 26500, output: 380, thinking: 150, requests: 1, model: 'gemini-3.5-flash');
    const RunUsage whole = RunUsage(input: 48200, cached: 31000, output: 18800, thinking: 12979, requests: 9, model: 'gemini-3.5-flash');
    Widget table(TextDirection d) => Directionality(
          textDirection: d,
          child: UsageTable(
            rows: const <UsageRow>[UsageRow('هذه الرسالة', mine), UsageRow('التشغيل كله', whole)],
            caption: usageCaption(whole),
          ),
        );
    await tester.binding.setSurfaceSize(const Size(390, 420));
    await tester.pumpWidget(MaterialApp(
      theme: base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'DejaVu')),
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFF000000),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              const Text('RTL', style: TextStyle(color: Colors.white)),
              table(TextDirection.rtl),
              const SizedBox(height: 18),
              const Text('LTR', style: TextStyle(color: Colors.white)),
              table(TextDirection.ltr),
            ]),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.runAsync(() async {
      final RenderRepaintBoundary b = tester.renderObject(find.byKey(key)) as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 2);
      final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$art/usage.png').writeAsBytes(bd!.buffer.asUint8List());
    });
  });
}
EOF
mkdir -p "$DS_ART"
flutter test test/usage_render_test.dart 2>&1 | tail -15
ls -la "$DS_ART"
