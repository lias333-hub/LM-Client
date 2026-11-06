#!/usr/bin/env python3
"""Rules conformance matrix: joins ci/rules.json with the emulator probe log (4_probe.txt).
usage: rules_matrix.py <probe log> <rules.json>   (prints the table; last line is RULES-MATRIX-RESULT)"""
import json
import re
import sys

probe = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
spec = json.load(open(sys.argv[2], encoding='utf-8'))
suites = {}
for line in probe:
    m = re.match(r'^(SECRETS|ENGINE|E2E|TRACE|PLAN|KEEPALIVE|SKILLS|SSH|RULES) (OK  |FAIL) (.*)$', line)
    if m:
        suites.setdefault(m.group(1), []).append((m.group(2).strip() == 'OK', m.group(3)))
gaps = [l for l in probe if l.startswith('RULES GAP')]


def lines_for(ref):
    suite, _, key = ref.partition(':')
    rows = suites.get(suite, [])
    if suite == 'RULES':
        return [r for r in rows if r[1].startswith('[%s]' % key)]
    return [r for r in rows if r[1].startswith(key)]


counts = {'VERIFIED': 0, 'FAILED': 0, 'MISSING': 0, 'UNTESTED': 0, 'PROMPT': 0, 'GAP': 0}
out = []
for r in spec['rules']:
    cls = r['class']
    tests = r.get('tests', [])
    found = [(t, lines_for(t)) for t in tests]
    missing = [t for t, rows in found if not rows]
    failed = [t for t, rows in found if any(not ok for ok, _ in rows)]
    n_lines = sum(len(rows) for _, rows in found)
    if cls == 'gap':
        status = 'GAP'
    elif cls == 'prompt':
        status = 'PROMPT'
    elif not tests:
        status = 'UNTESTED'
    elif failed:
        status = 'FAILED'
    elif missing:
        status = 'MISSING'
    else:
        status = 'VERIFIED'
    counts[status] += 1
    extra = ''
    if failed:
        extra = ' | failed: ' + ', '.join(failed)
    elif missing and cls != 'gap':
        extra = ' | no result for: ' + ', '.join(missing)
    elif cls == 'prompt':
        extra = ' | obedience NOT verified by the harness; detector: %s%s' % (r.get('detector', '-'), '' if not missing else ' (detector test missing!)')
        if missing:
            counts['MISSING'] += 1
    elif cls == 'gap':
        extra = ' | known gap, see GAP lines'
    out.append('%-9s %-8s %s  [%d check lines]%s' % (status, r['id'], r['text'], n_lines, extra))

print('RULES MATRIX (H0b): code = enforced by the harness, prompt = enforced only by the model, gap = documented hole')
print('')
order = ['FAILED', 'MISSING', 'UNTESTED', 'GAP', 'PROMPT', 'VERIFIED']
for st in order:
    for l in out:
        if l.startswith(st + ' '):
            print(l)
print('')
if gaps:
    print('Known gaps reported by the suite:')
    for g in gaps:
        print('  ' + g)
    print('')
print('RULES-MATRIX code_verified=%d code_failed=%d code_missing=%d code_untested=%d prompt_only=%d known_gaps=%d' % (
    counts['VERIFIED'], counts['FAILED'], counts['MISSING'], counts['UNTESTED'], counts['PROMPT'], counts['GAP']))
print('RULES-MATRIX-RESULT: ' + ('PASS' if not (counts['FAILED'] or counts['MISSING'] or counts['UNTESTED']) else 'FAIL'))
