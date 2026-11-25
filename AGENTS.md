# fischs — repo notes

Luau executor scripts for Roblox Fisch (`16732694052`). Read this before editing.

## Style

- 4 spaces, no tabs. `snake_case` for locals and functions, `CamelCase` keys in
  `CONFIG` (the GUI and docs both read that table).
- One file per tool, no external UI library, no `Illustrate`/`WindUI` imports.
- Comment the *why*: why a probe exists, what a guard catches, where a constant
  came from. Never narrate what the next line does.
- `log()`/`warn()` prefix is `[fisch]`, probe is `[fisch:probe]`.

## Hard rules

- `fisch.lua` must compile under Luau: `luau-compile --binary fisch.lua`.
- No `TODO`, no stubs, no "implement here". If a value is game-side and unknown,
  it goes in `CONFIG` with a pattern list, not a hole.
- Every loop that touches workspace or PlayerGui has a clock or iteration
  ceiling, and fails closed: on bad read, release the mouse and leave stage
  `error`.
- Every mouse press has a matching release on all exits, including `pcall`
  failure and `CharacterAdded`.
- Place check stays at the top of `fisch.lua`; do not widen it.
- Input simulation over remotes. Only add a remote path when input simulation
  demonstrably cannot reach the feature, and name the consequence in a comment.

## Files

- `fisch.lua` — suite. Config block first, then utilities, input, discovery,
  engine, GUI, loops, keys. Keep that order.
- `loader.lua` — mirrors `fisch.lua` from `main`, `master`, jsDelivr. Bump
  nothing; cache-bust is `os.time()`.
- `probe.lua` — read-only. Never add writes, teleports, or GUI there.

## Verify before commit

```powershell
luau-compile --binary fisch.lua
luau-compile --binary loader.lua
luau-compile --binary probe.lua
```
