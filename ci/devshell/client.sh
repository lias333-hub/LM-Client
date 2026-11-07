#!/usr/bin/env bash
# Client side of the dev shell (runs in the Claude sandbox). Usage:
#   client.sh start [branch=merge-a]      start a session (pushes branch dev-shell) and wait until it is ready
#   client.sh run [-t secs] 'command'     run a command on the box (default timeout 900 s); prints the output
#   client.sh run [-t secs] -f script.sh  same, from a file
#   client.sh wait <seq> [secs]           wait for the result of a command that was still running
#   client.sh art <seq> [dir]             download the artifacts a command left in $DS_ART
#   client.sh status                      session state
#   client.sh stop                        end the session
# Everything travels through public git branches (shell-in / shell-out): no secrets in commands.
set -u
MAIN="${DS_MAIN:-/home/claude/lm-client}"
H="${DS_HOME:-$HOME/.devshell}"
REMOTE="${DS_REMOTE:-$(git -C "$MAIN" remote get-url origin)}"
SLUG="${DS_SLUG:-lias333-hub/LM-Client}"
IN="$H/in"; OUTL="$H/out"
mkdir -p "$H"
export GIT_AUTHOR_NAME=ds-client GIT_AUTHOR_EMAIL=ds-client@users.noreply.github.com GIT_COMMITTER_NAME=ds-client GIT_COMMITTER_EMAIL=ds-client@users.noreply.github.com
TRAILERS=$'\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\nClaude-Session: https://claude.ai/code/session_01WnhsQJrEMyQko5ryM78a5G'

ensure_in() { [ -d "$IN/.git" ] || { mkdir -p "$IN"; git -C "$IN" init -q -b shell-in; git -C "$IN" remote add origin "$REMOTE"; }; }
ensure_out() { [ -d "$OUTL/.git" ] || { mkdir -p "$OUTL"; git -C "$OUTL" init -q; git -C "$OUTL" remote add origin "$REMOTE"; }; }
remote_sha() { git ls-remote "$REMOTE" "refs/heads/$1" 2>/dev/null | cut -f1; }
pull_out() { ensure_out; git -C "$OUTL" fetch -q --depth=1 origin "+shell-out:refs/remotes/origin/shell-out" 2>/dev/null; }
out_file() { git -C "$OUTL" show "origin/shell-out:out/$1" 2>/dev/null; }

wait_result() {  # wait_result <seq> <limit-seconds>
  local n="$1" limit="$2" name t0 last sha
  name=$(printf '%06d' "$n"); t0=$(date +%s); last=""
  while [ $(( $(date +%s) - t0 )) -lt "$limit" ]; do
    sha=$(remote_sha shell-out)
    if [ -n "$sha" ] && [ "$sha" != "$last" ]; then
      last="$sha"
      if pull_out && out_file "$name.txt" > "$H/last.txt"; then cat "$H/last.txt"; echo "[round-trip $(( $(date +%s) - t0 ))s]"; return 0; fi
    fi
    sleep 2
  done
  echo "[no result for $name after ${limit}s: still running? use: client.sh wait $n]"; return 2
}

cmd_start() {
  local br="${1:-merge-a}" max ts sha tree c t0 last sha2
  ensure_in
  max=0
  if [ -n "$(remote_sha shell-in)" ]; then
    git -C "$IN" fetch -q --depth=1 origin "+shell-in:refs/remotes/origin/shell-in" && git -C "$IN" reset -q --hard origin/shell-in
    max=$(ls -1 "$IN/cmd" 2>/dev/null | sed -n 's/^0*\([0-9][0-9]*\)\.sh$/\1/p' | sort -n | tail -1); max="${max:-0}"
  fi
  echo "$max" > "$H/seq"
  git -C "$MAIN" fetch -q origin "$br" || { echo "cannot fetch $br"; return 1; }
  sha=$(git -C "$MAIN" rev-parse FETCH_HEAD); tree=$(git -C "$MAIN" rev-parse 'FETCH_HEAD^{tree}')
  ts=$(date +%s)
  c=$(git -C "$MAIN" commit-tree "$tree" -p "$sha" -m "dev-shell start seq=$max ts=$ts branch=$br$TRAILERS")
  t0=$(date +%s)
  git -C "$MAIN" push -q -f origin "$c:refs/heads/dev-shell" 2>&1 | grep -v -E 'moved|github.com/lias|acknowledg|negotiation' 
  echo "started (ts=$ts, base seq=$max, branch=$br); waiting for ready..."
  last=""
  while [ $(( $(date +%s) - t0 )) -lt 540 ]; do
    sha2=$(remote_sha shell-out)
    if [ -n "$sha2" ] && [ "$sha2" != "$last" ]; then
      last="$sha2"
      if pull_out && out_file ready.txt 2>/dev/null | grep -q "start_ts=$ts "; then
        out_file ready.txt; echo "[ready after $(( $(date +%s) - t0 ))s]"
        if ! out_file ready.txt | grep -q 'prepare_rc=0'; then echo "--- prepare log tail"; out_file prepare.txt | tail -40; fi
        return 0
      fi
    fi
    sleep 5
  done
  echo "[not ready after 540s] status:"; out_file status.txt; return 2
}

cmd_run() {
  local to="" file="" body n name
  while [ $# -gt 0 ]; do
    case "$1" in
      -t) to="$2"; shift 2;;
      -f) file="$2"; shift 2;;
      *) break;;
    esac
  done
  if [ -n "$file" ]; then body=$(cat "$file"); else body="$*"; fi
  [ -n "$body" ] || { echo "no command"; return 1; }
  ensure_in
  [ -f "$H/seq" ] || echo 0 > "$H/seq"
  n=$(( $(cat "$H/seq") + 1 )); name=$(printf '%06d' "$n")
  mkdir -p "$IN/cmd"
  { [ -n "$to" ] && echo "# timeout=$to"; printf '%s\n' "$body"; } > "$IN/cmd/$name.sh"
  ls -1 "$IN/cmd" | head -n -40 | while read -r old; do rm -f "$IN/cmd/$old"; done
  git -C "$IN" add -A
  if git -C "$IN" rev-parse -q --verify HEAD >/dev/null 2>&1; then git -C "$IN" commit -q --amend --allow-empty -m "cmd $n$TRAILERS"; else git -C "$IN" commit -q --allow-empty -m "cmd $n$TRAILERS"; fi
  git -C "$IN" push -q -f origin shell-in 2>&1 | grep -v -E 'moved|github.com/lias|acknowledg|negotiation'
  echo "$n" > "$H/seq"
  wait_result "$n" $(( ${to:-900} + 90 ))
}

cmd_status() {
  pull_out && { echo "-- box:"; out_file status.txt; out_file ready.txt; }
  echo "-- run:"; gh api "repos/$SLUG/actions/runs?branch=dev-shell&per_page=1" -q '.workflow_runs[0] | "\(.status) \(.conclusion // "-") run#\(.run_number) id=\(.id) started=\(.run_started_at)"' 2>&1 | head -2
}

cmd_art() {
  local n="$1" dir="${2:-$H/art}" name; name=$(printf '%06d' "$n")
  pull_out; mkdir -p "$dir"
  git -C "$OUTL" archive "origin/shell-out" "art/$name" 2>/dev/null | tar -x -C "$dir" && echo "saved to $dir/art/$name" && ls -la "$dir/art/$name"
}

case "${1:-}" in
  start) shift; cmd_start "$@";;
  run) shift; cmd_run "$@";;
  wait) wait_result "$2" "${3:-600}";;
  art) shift; cmd_art "$@";;
  status) cmd_status;;
  stop) cmd_run -t 60 '# ds-exit';;
  *) sed -n '2,11p' "$0";;
esac
