# timeout=900
time flutter build apk --release 2>&1 | tail -2; APK=build/app/outputs/flutter-apk/app-release.apk; ls -la $APK; P=$(emu pkg $APK); echo pkg=$P; emu install $APK; emu launch $P >/dev/null; sleep 8; emu status | tail -1; emu shot final; emu crash | head -3; echo crash-check-done
