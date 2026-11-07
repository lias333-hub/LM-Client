# timeout=300
echo "--- ui"; emu ui | head -8; echo "--- tapt Terminal"; emu tapt Terminal; echo rc=$?; echo "--- tap terminal tab by coords"; emu tap 264 346; sleep 2; emu shot terminal; echo "--- back to chat tab, tap field, type"; emu tap 790 346; sleep 1; emu tap 540 2112; sleep 1; emu text "hello from emu"; sleep 1; emu shot typed; echo "--- burst"; emu burst 2 1; emu status | tail -1
