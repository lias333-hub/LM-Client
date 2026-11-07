# timeout=900
time flutter build apk --release --build-number=999 --dart-define=LM_BUILD=devshell 2>&1 | tail -15; ls -la build/app/outputs/flutter-apk/ 2>/dev/null | tail -3
