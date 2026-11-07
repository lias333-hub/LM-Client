# timeout=400
ls /usr/share/fonts/truetype/noto | head -8
FL=$(dirname $(dirname $(which flutter)))/bin/cache/artifacts/material_fonts
mkdir -p test
cat > test/ds_probe_test.dart <<'DART'
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _load(String family, String path) async {
  final l = FontLoader(family)..addFont(Future<ByteData>.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await l.load();
}

void main() {
  testWidgets('render arabic + latin', (WidgetTester t) async {
    final fl = Platform.environment['FL']!;
    await _load('Roboto', '$fl/Roboto-Regular.ttf');
    await _load('MaterialIcons', '$fl/MaterialIcons-Regular.otf');
    await _load('Arab', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    t.view.physicalSize = const Size(1080, 1200);
    t.view.devicePixelRatio = 2.5;
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: const ['Arab'])),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('الملخّص · 7 خطوات')),
            body: ListView(padding: const EdgeInsets.all(16), children: const [
              ListTile(leading: Icon(Icons.terminal), title: Text('Print current working directory'), subtitle: Text('pwd')),
              ListTile(leading: Icon(Icons.warning_amber, color: Colors.redAccent), title: Text('Write todo.sh script'), subtitle: Text('Path not allowed for this agent · فشلت')),
              Text('حجم الملف KB 1.5 داخل نص عربي', style: TextStyle(fontSize: 18)),
            ]),
          ),
        ),
      ),
    ));
    await t.pump();
    await t.runAsync(() async {
      final RenderRepaintBoundary b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image img = await b.toImage(pixelRatio: 1.0);
      final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.png);
      final art = Platform.environment['DS_ART']!;
      File('$art/probe.png').writeAsBytesSync(d!.buffer.asUint8List());
    });
  });
}
DART
FL=$FL flutter test test/ds_probe_test.dart 2>&1 | tail -15
ls -la $DS_ART
