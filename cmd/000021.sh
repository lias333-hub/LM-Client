# timeout=900
export JAVA_HOME=$JAVA_HOME_17_X64; export PATH=$JAVA_HOME/bin:$PATH; java -version 2>&1|head -1; time flutter build apk --release 2>&1 | tail -4; ls -la build/app/outputs/flutter-apk/*.apk; echo; emu pkg build/app/outputs/flutter-apk/app-release.apk
