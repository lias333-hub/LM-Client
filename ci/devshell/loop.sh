#!/usr/bin/env bash
# Runs on the GitHub runner (see .github/workflows/dev-shell.yml). Executes commands that the client
# pushes to branch `shell-in` (cmd/NNNNNN.sh, in order) and publishes results to branch `shell-out`
# (out/NNNNNN.txt, out/ready.txt, out/status.txt, art/NNNNNN/*). Both branches are force-pushed single commits.
# Everything is PUBLIC (public repo): never put secrets in commands or outputs.
set -u
: "${GITHUB_WORKSPACE:?}"
export DS_REPO="$GITHUB_WORKSPACE"
T0=$(date +%s)
TOKEN="${GH_TOKEN:-}"
REMOTE="${DS_REMOTE:-https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY:-x/x}.git}"
POLL="${POLL:-4}"
IDLE_MAX="${IDLE_MAX:-720}"
IN=/tmp/ds-in; OUT=/tmp/ds-out; BIN=/tmp/dsbin; ART=/tmp/ds-art
mkdir -p "$BIN" "$ART"
cp -r "$DS_REPO"/ci/devshell/bin/. "$BIN"/ && chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
git config --global user.name ds-bot
git config --global user.email ds-bot@users.noreply.github.com

SUBJ=$(git -C "$DS_REPO" log -1 --format=%s 2>/dev/null)
START_SEQ=$(printf '%s' "$SUBJ" | sed -n 's/.*seq=\([0-9][0-9]*\).*/\1/p'); START_SEQ="${START_SEQ:-0}"
START_TS=$(printf '%s' "$SUBJ" | sed -n 's/.*ts=\([0-9][0-9]*\).*/\1/p'); START_TS="${START_TS:-0}"

redact() { if [ -n "$TOKEN" ]; then sed "s|$TOKEN|***|g"; else cat; fi; }

rm -rf "$OUT"; mkdir -p "$OUT/out"
git -C "$OUT" init -q -b shell-out
git -C "$OUT" remote add origin "$REMOTE"
publish() {
  git -C "$OUT" add -A
  if git -C "$OUT" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    git -C "$OUT" commit -q --amend --allow-empty -m out
  else
    git -C "$OUT" commit -q --allow-empty -m out
  fi
  git -C "$OUT" push -q -f origin shell-out 2>&1 | redact | tail -2
}
status() { echo "$*" > "$OUT/out/status.txt"; }

status "phase=setup start_ts=$START_TS at=$(date -u +%FT%TZ)"
publish

S0=$(date +%s)
( dprep ) > /tmp/dprep.log 2>&1
PRC=$?
S1=$(date +%s)
tail -c 100000 /tmp/dprep.log | redact > "$OUT/out/prepare.txt"
echo "start_ts=$START_TS prepare_rc=$PRC prepare_secs=$((S1-S0)) loop_secs=$((S1-T0)) $(flutter --version 2>/dev/null | head -1)" > "$OUT/out/ready.txt"
status "phase=ready start_ts=$START_TS at=$(date -u +%FT%TZ)"
publish

pull_in() {
  [ -d "$IN/.git" ] || { rm -rf "$IN"; mkdir -p "$IN"; git -C "$IN" init -q; git -C "$IN" remote add origin "$REMOTE"; }
  git -C "$IN" fetch -q --depth=1 origin "+shell-in:refs/remotes/origin/shell-in" 2>/dev/null || return 1
  git -C "$IN" reset -q --hard origin/shell-in
}

run_one() {
  local n="$1" f="$2" name TO a b rc
  name=$(printf '%06d' "$n")
  if sed -n '1,5p' "$f" | grep -q '^# ds-exit'; then
    echo "seq=$n rc=0 secs=0 ended on request" > "$OUT/out/$name.txt"
    status "phase=ended reason=requested at=$(date -u +%FT%TZ)"; publish; exit 0
  fi
  TO=$(sed -n '1,5s/^# timeout=\([0-9][0-9]*\).*/\1/p' "$f" | head -1); TO="${TO:-900}"
  a=$(date +%s)
  ( cd "$DS_REPO" && env -u GH_TOKEN -u GITHUB_TOKEN DS_ART="$ART" timeout -k 10 "$TO" bash "$f" < /dev/null ) > /tmp/cmd.out 2>&1
  rc=$?
  b=$(date +%s)
  { echo "seq=$n rc=$rc secs=$((b-a)) at=$(date -u +%FT%TZ)"; tail -c 200000 /tmp/cmd.out; } | redact > "$OUT/out/$name.txt"
  if [ -n "$(ls -A "$ART" 2>/dev/null)" ]; then mkdir -p "$OUT/art/$name"; cp -r "$ART"/. "$OUT/art/$name"/; rm -rf "${ART:?}"/*; fi
  ls -1 "$OUT/out" | grep -E '^[0-9]{6}\.txt$' | head -n -30 | while read -r old; do rm -f "$OUT/out/$old"; done
  ls -1d "$OUT"/art/* 2>/dev/null | head -n -8 | while read -r old; do rm -rf "$old"; done
  status "phase=idle last_seq=$n start_ts=$START_TS at=$(date -u +%FT%TZ)"
  publish
}

last="$START_SEQ"; lastact=$(date +%s); insha=""
while :; do
  now=$(date +%s)
  if [ $((now - lastact)) -gt "$IDLE_MAX" ]; then
    status "phase=ended reason=idle after=${IDLE_MAX}s at=$(date -u +%FT%TZ)"; publish; exit 0
  fi
  sha=$(git ls-remote "$REMOTE" refs/heads/shell-in 2>/dev/null | cut -f1)
  if [ -n "$sha" ] && [ "$sha" != "$insha" ]; then
    if pull_in; then insha="$sha"; fi
  fi
  next=$((last + 1))
  f="$IN/cmd/$(printf '%06d' "$next").sh"
  if [ -f "$f" ]; then
    run_one "$next" "$f"
    last="$next"; lastact=$(date +%s)
    continue
  fi
  sleep "$POLL"
done
