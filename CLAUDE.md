# Beat Deck Survivors (Godot 4.7)

Hybrid of Vampire Survivors (auto-battle swarm), Slay the Spire (map run, deck, relics, shop, events, upgrades) and a rhythm game (cards played on the beat).

## Environment
- Godot: user env vars `GODOT` (console exe) and `GODOT_GUI`. Installed via winget (GodotEngine.GodotEngine). New bash shells may lack them: export manually from `$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_*/`.
- Run: `./tools/run.ps1`   Smoke test: `./tools/test.ps1` (headless bot plays a full run; must print `AUTOTEST result`).
- Bot variants: `-- --autotest` (map run), `-- --autotest --endless`. Multi-run: `./tools/balance.ps1 -N 6`.
- Screenshot a screen (non-headless): `"$GODOT" --path . -- --screen=<menu|mode|char|settings|map|reward|shop|event|rest|pick|end|battle|elite|boss> --shot=<abs path.png>` then view the PNG.
- Re-import after adding assets: `"$GODOT" --headless --path . --import`.
- Autotest/--screen runs never write user settings (see `Settings.save_cfg`).

## Layout (scripts/)
- `main.gd` game flow + all menu/map/shop/event/etc. screens (immediate-mode UI drawn in `draw_hud`).
- `battle.gd` one real-time battle: simulation, juice (particles, shake, hitstop, vignette), card effects (`_apply_card`), world + battle HUD drawing.
- `ui.gd` immediate-mode buttons/cards/sliders; `hud.gd` is the Control that calls `main.draw_hud`.
- `cards.gd` card DB (`def(id)` resolves upgrades, id+"+" = upgraded; params in `p`, desc templates), `relics.gd`, `characters.gd`, `run_state.gd`, `map_gen.gd`, `deck.gd`.
- `conductor.gd` autoload: beat clock, music + SFX buses, `beat` signal, `beat_offset()`. `settings.gd` autoload: user://settings.cfg (volumes, offset, shake, fullscreen, stats).

## Adding content
- Card: add to `Cards.DB` (+ `match` arm in `Battle._apply_card`). Relic: add to `Relics.DB` and check `run.has_relic("id")` where it applies.
- Event: add to `Main._events()` and a case in `_event_choice`.

## Conventions
- UI text is Japanese using DotGothic16 (OFL). Visuals + SFX are Kenney CC0, BGM is Joth CC0 (see assets/CREDITS.md). New external assets must be CC0/permissive and recorded there.
- Avoid `:=` on Variant values (dict/array access) - GDScript treats that as a parse error.
- Commit small, after `./tools/test.ps1` passes.
