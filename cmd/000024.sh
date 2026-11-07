# timeout=300
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do emu key DEL; done; sleep 1; emu text "abcdefghij klmnop 12345"; sleep 2; emu shot t1; for i in $(seq 1 25); do emu key DEL; done; sleep 1; emu sh "input text hello_from_emu_end"; sleep 2; emu shot t2
