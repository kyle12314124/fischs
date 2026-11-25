# fischs

Roblox **Fisch** (place `16732694052`) automation for an executor. One Luau file,
no external UI library, no RemoteEvent names — casting, reeling and the minigame
run through simulated mouse input, so a game-side rename cannot break the loop.

```
loader.lua   paste this into the executor
fisch.lua    the suite itself (loaded by loader.lua)
probe.lua    name dumper — run when auto-detection needs a nudge
```

## Quick start

Paste into Delta / Wave / Synapse-class executor and execute:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/kyle12314124/fischs/main/loader.lua"))()
```

The loader tries `main`, `master`, then jsDelivr, and cache-busts on `os.time()`.
Or paste `fisch.lua` directly.

The client must allow synthetic input. If the panel appears but nothing casts,
the executor is dropping `VirtualInputManager` — enable mouse input in executor
settings, then re-execute.

## Keys

| Key | Action |
|---|---|
| `RightShift` | show / hide the panel |
| `F` | arm / disarm auto-fish |
| `F2` | hide mode (removes the panel; loops keep running) |
| `End` | panic — unload, release the mouse, restore walk speed |

## Chips

`FISH` casts, watches the bobber, reels, plays the minigame, repeats.
`SELL` teleports to the nearest merchant and clicks the sell button.
`SPEED` 48 walk speed, 50 jump power.
`ESP` highlights the bobber with a distance label.

## How it works

The cast cycle is a small state machine: `casting -> waiting -> reeling ->
minigame -> idle`, each stage with its own clock ceiling, wrapped in `pcall` so
an error releases the mouse instead of leaving it held down.

- **Bite**: bobber Y drop > `BiteDrop`, bobber despawn, or a minigame frame
  appearing. Whichever lands first.
- **Minigame**: no hard-coded GUI path. `calibrate()` presses once, measures
  which `GuiObject` moved under input (the bar) and which moved on its own (the
  marker), and records whether holding raises or lowers the bar. Steering is a
  deadband controller with velocity lead. If calibration finds nothing, it falls
  back to a fixed pulse rhythm (`PulseHold` / `PulseRest`).
- **Detection**: names are runtime-scanned with pattern lists in `CONFIG`. The
  geometric minigame fallback only runs after a reel click, so a shop dialog
  cannot be mistaken for a bite.

## Tuning

Edit `CONFIG` at the top of `fisch.lua`. The ones worth touching first:

| Key | Default | Meaning |
|---|---|---|
| `CastDelayMin/Max` | 0.65 / 1.55 | jitter between casts |
| `BiteDrop` | 0.35 | studs the bobber must fall to count as a bite |
| `Deadband` | 0.045 | fraction of bar height; steering is ignored inside it |
| `LeadTime` | 0.09 | seconds of marker travel to aim ahead by |
| `PulseHold/Rest` | 0.34 / 0.16 | fallback rhythm when calibration fails |
| `MinigameTimeout` | 45 | hard ceiling on one minigame |
| `WalkSpeed` | 48 | only applied while `SPEED` is on |

Candidate name lists: `BobberNames`, `MinigameNames`, `MerchantNames`,
`SellButtonWords`. Run `probe.lua` in-game and paste the real names there if an
update renames something.

## probe.lua

No UI, no render loop, no writes. Three dumps, printed with `[fisch:probe]`:

- `F6` — PlayerGui tree, depth 4, 120 lines, class and size per node
- `F7` — parts whose name reads like a bobber, nearest first
- `F8` — merchant models, equipped tool, backpack contents

Cast first, then press `F7`; the bobber only exists mid-cast.

## Troubleshooting

- **Executed and nothing happened at all** — run `diag.lua`. It prints the place
  id, executor name, transport, fetch, compile and a live GUI mount test, so the
  first failing line names the cause. Most common result: `fetch FAILED`, which
  means the executor blocks `HttpGet`; use `request` in `loader.lua` or paste
  `fisch.lua` directly.
- **No panel but console shows `[fisch] v1.0 loaded`** — the executor strips
  ScreenGui. Re-run from `gethui` or switch executor.
- **Panel loads, nothing happens** — no mouse injection. Check executor input
  setting; the status line will read `stage casting` with `casts 0`.
- **Casts then immediately gives up** — `no bobber`. Run `probe.lua` → `F7` and
  add the part name to `BobberNames`.
- **Minigame never resolves** — calibration misses. Lower `PulseRest`, or set
  `MinigameNames` from the `F6` dump. `MinigameTimeout` keeps it bounded either
  way.
- **Sell does nothing** — merchant model missing or the dialog needs a different
  key. Set `SellKey`; check `F8` for the model name.
- **Second execution kills the first** — expected; each execution owns its own
  loops and `End` unloads the newest instance only.

## Layout

```
fisch.lua    one file: config, input, cast engine, sell, movement, ESP, GUI
loader.lua   mirror loader + cache bust
probe.lua    read-only in-game dumper
diag.lua     capability doctor, run when nothing shows
```
