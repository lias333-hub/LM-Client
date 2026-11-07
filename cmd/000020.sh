# timeout=600
flutter build apk --release 2>&1 | grep -v "^\s*$" | sed -n "1,22p"; echo ====; java -version 2>&1 | head -1; flutter config 2>&1 | grep -i jdk; echo "JAVA17=$JAVA_HOME_17_X64"
