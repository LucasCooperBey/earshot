#!/usr/bin/env bash
# source: earshot --stop kills only the playback PID recorded in the state file,
# so an unrelated process named say stays alive; the /api/generate body includes
# "think":false; an empty model reply is announced and the planted reply is spoken.
# A copied /bin/sleep will not stay running on this Mac (the kernel rejects the
# arm64e platform binary), so the sleeper is a small program named say that
# sleeps 300 seconds. Its process name is say, which is the name the old
# stop path would have matched.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EARSHOT="$ROOT/bin/earshot"
ORIG_PATH="${PATH}"
failures=0
UNRELATED=""
PLAYBACK=""

cleanup() {
  if [ -n "$UNRELATED" ]; then
    kill "$UNRELATED" 2>/dev/null || true
    wait "$UNRELATED" 2>/dev/null || true
  fi
  if [ -n "$PLAYBACK" ]; then
    kill "$PLAYBACK" 2>/dev/null || true
    wait "$PLAYBACK" 2>/dev/null || true
  fi
}
trap cleanup EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

is_alive() {
  local st
  st="$(ps -p "$1" -o state= 2>/dev/null | awk 'NR==1 { print $1 }')"
  case "$st" in
    ""|Z*) return 1 ;;
    *) return 0 ;;
  esac
}

ucomm_of() {
  ps -p "$1" -o ucomm= 2>/dev/null | awk 'NR==1 { print $1 }'
}

new_case() {
  CASE="$(mktemp -d)"
  export HOME="$CASE/home"
  export EARSHOT_STATE="$CASE/state"
  export EARSHOT_CONFIG=/dev/null
  export EARSHOT_TEST_CAPTURE="$CASE/capture"
  export LLM_URL="http://localhost:11434"
  export LLM_MODEL="llama3.2:3b"
  mkdir -p "$HOME" "$EARSHOT_STATE" "$CASE/bin" "$CASE/capture"
  export PATH="$CASE/bin:$ORIG_PATH"
  unset TTS_URL EARSHOT_VOICE EARSHOT_FILE EARSHOT_SOURCE EARSHOT_HOME EARSHOT_SPEED PROMPT_FILE MAX_CHARS LLM_KEEPALIVE
  cat >"$CASE/bin/say" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >"$EARSHOT_TEST_CAPTURE/say.args"
EOF
  chmod +x "$CASE/bin/say"
  cat >"$CASE/bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' '{"response":""}'
EOF
  chmod +x "$CASE/bin/curl"
}

wait_say() {
  local i=0
  while [ "$i" -lt 50 ] && [ ! -s "$CASE/capture/say.args" ]; do
    i=$((i + 1))
    sleep 0.1
  done
}

case_stop() {
  local name="stop touches only earshot playback"
  UNRELATED=""
  PLAYBACK=""
  if grep -q 'pkill -x' "$EARSHOT"; then
    fail "$name: refused to run because pkill -x is still in bin/earshot"
    return
  fi
  new_case
  if ! command -v cc >/dev/null 2>&1; then
    fail "$name: cc is missing, so no long-running process named say was started"
    return
  fi
  cat >"$CASE/sleeper.c" <<'EOF'
#include <unistd.h>
int main(void) { sleep(300); return 0; }
EOF
  if ! cc -o "$CASE/sleeper" "$CASE/sleeper.c"; then
    fail "$name: could not compile the sleeper named say"
    return
  fi
  mkdir -p "$CASE/a" "$CASE/b"
  cp "$CASE/sleeper" "$CASE/a/say"
  cp "$CASE/sleeper" "$CASE/b/say"
  chmod +x "$CASE/a/say" "$CASE/b/say"
  "$CASE/a/say" &
  UNRELATED=$!
  "$CASE/b/say" &
  PLAYBACK=$!
  sleep 0.3
  if [ "$(ucomm_of "$UNRELATED")" != "say" ] || [ "$(ucomm_of "$PLAYBACK")" != "say" ]; then
    fail "$name: process name was not say (unrelated=$(ucomm_of "$UNRELATED") playback=$(ucomm_of "$PLAYBACK"))"
    return
  fi
  if ! is_alive "$UNRELATED" || ! is_alive "$PLAYBACK"; then
    fail "$name: a sleeper exited before stop"
    return
  fi
  printf '%s\n' "$PLAYBACK" >"$EARSHOT_STATE/play.pid"
  bash "$EARSHOT" --stop >"$CASE/capture/stdout" 2>"$CASE/capture/stderr" || true
  local i=0
  while is_alive "$PLAYBACK" && [ "$i" -lt 20 ]; do
    i=$((i + 1))
    sleep 0.1
  done
  if is_alive "$PLAYBACK"; then
    fail "$name: playback pid still alive"
  elif ! is_alive "$UNRELATED"; then
    fail "$name: unrelated say was killed"
  else
    pass "$name"
  fi
  kill "$UNRELATED" 2>/dev/null || true
  wait "$UNRELATED" 2>/dev/null || true
  UNRELATED=""
  wait "$PLAYBACK" 2>/dev/null || true
  PLAYBACK=""
}

case_think() {
  local name="generate body sends think false"
  local why=""
  new_case
  printf '%s' 'planted reply for the think case' >"$CASE/reply.txt"
  cat >"$CASE/bin/curl" <<'EOF'
#!/bin/sh
prev=""
src=""
for a in "$@"; do
  if [ "$prev" = "-d" ]; then
    case "$a" in
      @*) src=${a#@} ;;
    esac
  fi
  prev=$a
done
if [ -n "$src" ]; then
  cp "$src" "$EARSHOT_TEST_CAPTURE/body.json" || exit 1
fi
printf '%s\n' '{"response":"stub briefing"}'
EOF
  chmod +x "$CASE/bin/curl"
  export EARSHOT_SOURCE=file
  export EARSHOT_FILE="$CASE/reply.txt"
  bash "$EARSHOT" >"$CASE/capture/stdout" 2>"$CASE/capture/stderr" || true
  wait_say
  if [ ! -f "$CASE/capture/body.json" ]; then
    why="request body was not captured"
  elif ! grep -q -F '"think":false' "$CASE/capture/body.json"; then
    why='body missing "think":false'
  elif ! jq -e '.think == false' "$CASE/capture/body.json" >/dev/null 2>&1; then
    why="think field is not false"
  elif ! grep -qxF 'stub briefing' "$CASE/capture/say.args"; then
    why="say was not given stub briefing"
  fi
  if [ -n "$why" ]; then fail "$name: $why"; else pass "$name"; fi
}

case_empty() {
  local name="empty summary is announced"
  local why=""
  local reply="planted reply spoken when the summary is empty"
  local expect
  new_case
  expect="earshot: no summary from ${LLM_MODEL} at ${LLM_URL}; speaking the reply as is"
  printf '%s' "$reply" >"$CASE/reply.txt"
  cat >"$CASE/bin/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$CASE/bin/curl"
  export EARSHOT_SOURCE=file
  export EARSHOT_FILE="$CASE/reply.txt"
  bash "$EARSHOT" >"$CASE/capture/stdout" 2>"$CASE/capture/stderr" || true
  wait_say
  if ! grep -qxF "$expect" "$CASE/capture/stderr"; then
    why="stderr missing the no summary line"
  elif ! grep -qF 'speaking reply as is' "$CASE/capture/stdout"; then
    why="stdout did not say speaking reply as is"
  elif ! grep -qxF "$reply" "$CASE/capture/say.args"; then
    why="say was not given the planted reply"
  elif ! grep -qxF "$expect" "$EARSHOT_STATE/earshot.log"; then
    why="log missing the no summary line"
  fi
  if [ -n "$why" ]; then fail "$name: $why"; else pass "$name"; fi
}

case_stop
case_think
case_empty

if [ "$failures" -eq 0 ]; then
  exit 0
fi
exit 1
