# timeout=300
APK=build/app/outputs/flutter-apk/app-release.apk; emu status | head -2; echo --install; time emu install $APK; echo --launch; emu launch com.lmclient.lm_client; sleep 8; emu status | tail -1; emu shot first; echo --crash; emu crash | head -5; echo --log; emu log 15
