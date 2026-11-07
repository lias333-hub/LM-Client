# timeout=400
grep -n "dev_dependencies" -A4 pubspec.yaml | head -8
if grep -q "^dev_dependencies:" pubspec.yaml; then
  python3 - <<'PY'
import re
s=open('pubspec.yaml').read()
if 'flutter_test:' not in s:
    s=s.replace('dev_dependencies:\n','dev_dependencies:\n  flutter_test:\n    sdk: flutter\n',1)
open('pubspec.yaml','w').write(s)
PY
else
  printf '\ndev_dependencies:\n  flutter_test:\n    sdk: flutter\n' >> pubspec.yaml
fi
flutter pub get 2>&1 | tail -3
FL=$(dirname $(dirname $(which flutter)))/bin/cache/artifacts/material_fonts FL=$FL flutter test test/ds_probe_test.dart 2>&1 | tail -12
ls -la $DS_ART
