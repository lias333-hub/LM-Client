set -e
grep -q "flutter_test" pubspec.yaml || printf '\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n' >> pubspec.yaml
flutter pub get 2>&1 | tail -1
flutter test test/usage_render_test.dart 2>&1 | tail -12
ls -la "$DS_ART"
