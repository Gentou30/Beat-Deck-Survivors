# Beat Deck Survivors (Godot 4.7)

Hybrid of Vampire Survivors (auto-battle swarm), Slay the Spire (deck, energy, card rewards) and a rhythm game (cards are played on the beat).

## Environment
- Godot: user env vars `GODOT` (console exe) and `GODOT_GUI`. Installed via winget (GodotEngine.GodotEngine).
- Run: `./tools/run.ps1`   Smoke test: `./tools/test.ps1` (headless bot, must print `AUTOTEST result`).
- Screenshot check: `"$GODOT" --path . -- --autotest --shot=<abs path.png>` (non-headless), then view the PNG.
- Re-import after adding assets: `"$GODOT" --headless --path . --import`.

## Layout
- `scripts/conductor.gd` autoload: beat clock, procedural music/SFX, `beat` signal, `beat_offset()`.
- `scripts/cards.gd` card database (add cards here + a `match` arm in `main.gd:_apply_card`).
- `scripts/deck.gd` draw/discard/hand logic.
- `scripts/main.gd` game loop, waves, drawing (world `_draw`, HUD `draw_hud`).
- `docs/DESIGN.md` design + roadmap.

## Conventions
- UI text is English (Godot's default font has no CJK glyphs; add a font asset to localize).
- Assets are currently procedural. External assets must be CC0/permissive and recorded in `assets/CREDITS.md`.
- Commit small, after `./tools/test.ps1` passes.
