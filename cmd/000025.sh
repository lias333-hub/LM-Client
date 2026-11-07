# timeout=600
echo "--- start while running"; emu start 2>&1 | head -3; echo "--- stop"; time emu stop; sleep 3; emu status; echo "rc=$?"; pgrep -fa qemu-system | head -2; echo "--- restart (image already installed)"; time emu start 2>&1 | tail -5
