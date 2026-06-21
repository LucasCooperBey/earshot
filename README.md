# earshot

**Hear the action-first TL;DR of your AI coding agent's last reply.** Hit one key and get a spoken briefing that leads with what *you* need to do — the decision, the thing to approve, the option to pick — then the bottom-line result. The code, the reasoning, the back-and-forth: stripped. Fully local, no API keys, works offline.

Agent responses are long. Usually you only need two things: *is there an action for me, and what happened?* earshot speaks exactly that so you can listen and keep moving instead of scanning a wall of text.

## What it does

- `earshot` — summarize + speak your agent's last response, action-first.
- `earshot say [text]` — narrate any text, stdin, or the clipboard, verbatim.
- `earshot --warm` — preload the model so the next call is instant.
- `earshot --stop` — stop playback. `earshot --dry` — preview, no audio.

In **Claude Code** it installs as two slash commands: **`/.`** (summary) and **`/say`** (raw).

## How it works

```
last agent response  →  local LLM distills it action-first  →  local TTS speaks it
(Claude Code transcript)        (ollama)                          (system voice or a TTS server)
```

Nothing leaves your machine. The distiller and voice are both pluggable, and you can point them at another box on your LAN/VPN if you'd rather run the model on a GPU.

## Install

```sh
git clone <repo-url> earshot && cd earshot && ./install.sh
```

**Required:** `python3`, `jq`, `curl`, and [ollama](https://ollama.com) + a small model (the summarizer — the installer offers to pull `llama3.2:3b`).
**Voice:** the built-in **system voice works with zero setup** (macOS `say` / Linux `espeak-ng`). For a natural neural voice, run a TTS server (below). `ffmpeg` is only needed for that path.

## Quickstart

```sh
earshot say "it works"          # raw narrate
earshot --warm                  # optional: preload the model
# then in Claude Code, after any reply:
/.
```

## Configuration

`~/.config/earshot/config` (see [`examples/config`](examples/config)):

| Key | Default | What |
|---|---|---|
| `EARSHOT_SPEED` | `1.5` | playback speed (try `2.0` for power skimming) |
| `LLM_MODEL` | `llama3.2:3b` | any ollama model (`gemma3:4b` is a touch sharper) |
| `LLM_URL` | `http://localhost:11434` | summarizer endpoint — or your own box |
| `TTS_URL` | *(empty → system voice)* | OpenAI-compatible TTS server for a better voice |
| `TTS_VOICE` | `af_nova` | voice name on the TTS server |
| `EARSHOT_SOURCE` | `claude-code` | `claude-code` \| `clipboard` \| `stdin` \| `file` |

Edit the distiller's instructions in [`prompts/summary.txt`](prompts/summary.txt) to change what it front-loads.

## A better voice

The system voice is instant but robotic. For a natural one, run an OpenAI-compatible TTS server — e.g. [kokoro-fastapi](https://github.com/remsky/Kokoro-FastAPI) — and set `TTS_URL=http://localhost:8880`. earshot will stream from it.

## Run the model elsewhere

Have a spare GPU box? Point `LLM_URL` / `TTS_URL` at it (`http://host:11434`, `http://host:8880`). earshot calls them over plain HTTP — reachable over your LAN or a VPN like Tailscale.

## Other agents

The default source reads the current **Claude Code** session transcript via `$CLAUDE_CODE_SESSION_ID`. Adapters for other agents (Codex, Cursor, …) are a small addition — PRs welcome. Until then, pipe anything in: `some-agent --json | jq -r .text | earshot say`.

## License

MIT.
