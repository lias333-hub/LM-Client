# timeout=900
java -version 2>&1 | head -1; echo JAVA_HOME=$JAVA_HOME; echo "--- cold emulator start"; time emu start 2>&1 | tail -6
