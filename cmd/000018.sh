# timeout=900
dsync emu-test >/dev/null && cp ci/devshell/bin/emu /tmp/dsbin/emu && time emu start
