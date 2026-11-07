# timeout=600
dsync merge-a
time flutter analyze lib --no-fatal-infos --no-fatal-warnings 2>&1 | tail -8
