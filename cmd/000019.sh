# timeout=900
time flutter build apk --release 2>&1 | tail -6; ls -la build/app/outputs/flutter-apk/ | head; echo; emu pkg build/app/outputs/flutter-apk/app-release.apk
