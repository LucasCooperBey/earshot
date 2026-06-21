#!/usr/bin/env bash
# earshot installer — idempotent. macOS + Linux.
set -u
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"; CFGDIR="$HOME/.config/earshot"; OS="$(uname -s)"
have(){ command -v "$1" >/dev/null 2>&1; }
ok(){ printf '  + %s\n' "$*"; }
warn(){ printf '  ! %s\n' "$*"; }

mkdir -p "$BIN" "$CFGDIR"
echo "earshot install"

ln -sf "$REPO/bin/earshot" "$BIN/earshot"; chmod +x "$REPO/bin/earshot"
ok "linked $BIN/earshot"
case ":$PATH:" in *":$BIN:"*) ;; *) warn "add $BIN to PATH:  export PATH=\"\$HOME/.local/bin:\$PATH\"";; esac

if [ -f "$CFGDIR/config" ]; then
  grep -q '^EARSHOT_HOME=' "$CFGDIR/config" || printf 'EARSHOT_HOME=%s\n' "$REPO" >> "$CFGDIR/config"
  ok "kept existing $CFGDIR/config"
else
  { printf 'EARSHOT_HOME=%s\n' "$REPO"; cat "$REPO/examples/config"; } > "$CFGDIR/config"
  ok "wrote $CFGDIR/config"
fi

echo "dependencies:"
for d in python3 jq curl; do have "$d" && ok "$d" || warn "$d  (REQUIRED)"; done
if have ffplay || have ffmpeg; then ok "ffplay"; else warn "ffmpeg  (only for a TTS-server voice)"; fi
have ollama && ok "ollama" || warn "ollama  (the summarizer) — https://ollama.com"
case "$OS" in
  Darwin) ok "macOS 'say' (built-in voice)";;
  *) have espeak-ng && ok "espeak-ng (system voice)" || warn "system voice: apt install espeak-ng";;
esac

if have ollama; then
  MODEL="$( . "$CFGDIR/config" 2>/dev/null; printf '%s' "${LLM_MODEL:-llama3.2:3b}")"
  if ollama list 2>/dev/null | grep -q "${MODEL%%:*}"; then
    ok "model $MODEL present"
  elif [ -t 0 ]; then
    printf '  pull summarizer model %s now? (~2GB) [y/N] ' "$MODEL"; read -r a
    case "$a" in y|Y) ollama pull "$MODEL";; *) warn "later:  ollama pull $MODEL";; esac
  else
    warn "run:  ollama pull $MODEL"
  fi
fi

if [ -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude/commands"
  for c in "..md" "say.md"; do
    dst="$HOME/.claude/commands/$c"
    [ -f "$dst" ] && cp "$dst" "$dst.pre-earshot.bak" 2>/dev/null && warn "backed up existing $c -> $c.pre-earshot.bak"
    cp "$REPO/commands/$c" "$dst" 2>/dev/null && ok "installed $c"
  done
fi

echo
echo "done.  try:  earshot say \"it works\"      then in Claude Code:  /."
