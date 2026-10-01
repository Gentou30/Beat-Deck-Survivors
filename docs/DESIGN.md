# Design

## Loop
1. 5 waves (28 s each; wave 5 = boss). Enemies spawn on every beat and chase you. A weak auto-bolt fires each beat.
2. Hand of 5 cards from your deck. Energy +1 every 2 beats (max 5). Play a card with 1-5 / click.
3. Timing grade vs nearest beat: PERFECT (<=70 ms) x1.5, GOOD (<=140 ms) x1.0, MISS x0.6 + combo reset. Combo adds +2% dmg each (max 20).
4. After each wave pick 1 of 3 cards (or rest +15 HP). Deck reshuffles discard when the draw pile empties.

## Roadmap ideas
- Real art/audio (CC0: Kenney, OpenGameArt) + CREDITS.md; real music with BPM/offset metadata.
- Latency calibration screen (currently `[` / `]` nudge offset).
- Card upgrades, relics, elites, map nodes (StS-style), more enemy types/patterns on beat.
- Card rarity, exhaust, status effects; save/meta progression; gamepad.
