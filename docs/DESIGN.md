# Design

## Core loop (battle)
Survivor-style arena. Enemies spawn on every beat and chase you; a weak auto-bolt fires each beat. Hand of 5 cards, energy +1 per 2 beats. Play cards (1-5/click) near a beat: PERFECT x1.5 (<=70 ms, +20 ms with Metronome), GOOD x1.0, MISS x0.6 + combo reset. Combo adds +2% dmg each (max 20).
Boss/elite telegraph ground slams on the beat grid (4-beat warning).

## Run structure (Climb mode)
10-floor branching map + boss. Nodes: battle, elite (relic), rest (heal 30% or upgrade a card), shop (cards, relics, removal), event, treasure (relic). Gold, card rewards after fights, 9 relics, 16 cards (attack/skill/power, upgrades "+", exhaust), 3 characters with passives.
Endless mode: waves forever; shop every 4 waves, rest every 3, elite every 5.

## Roadmap ideas
- More enemy behaviours (ranged/charger) and boss phases; act 2.
- More relics/events/cards, card rarity, potions, curses.
- Per-track BPM/offset metadata + track select; real hit-sound mixing.
- Gamepad support, achievements/unlocks.
