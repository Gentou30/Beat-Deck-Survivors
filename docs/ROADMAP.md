# Roadmap to "award quality"

Critique of the v0.3 state (what a juror/new player would hit first), then iterations.
Each iteration: implement -> bot/headless test -> screenshots -> commit.

## Critique
1. **Onboarding**: nothing explains the rhythm timing; a new player doesn't know what a good press looks like. (-> I1)
2. **Rhythm feedback**: no early/late info; judgement is only a word. (-> I1)
3. **Combat depth/variety**: few enemy behaviours (all "walk at you"), one boss; no ranged/charging threats, no bullet patterns on the beat. (-> I2)
4. **Peaks**: no big payoff moments (fever / ultimate) for chaining PERFECTs. (-> I2)
5. **Build depth**: 16 cards, 9 relics, no potions; few synergies. (-> I2)
6. **Presentation**: one arena look, little character animation, no bloom/glow, plain death anims. (-> I3)
7. **Replayability**: no unlocks, ascension (difficulty ladder), daily seed, achievements. (-> I4)
8. **Reach/accessibility**: Japanese only, no gamepad, no reduced-flash / assist options. (-> I5)
9. **Quality gates**: balance only checked by one bot style; no fuzz test of every screen/event. (-> I6)

## Iterations
- **I1 Onboarding + rhythm clarity**: interactive tutorial ("あそびかた"), early/late indicator, press-marker on the lane.
- **I2 Combat depth**: new enemy types (shooter/charger/splitter) with beat-telegraphed attacks, 3 bosses, Fever mode + Beat Drop ultimate, more cards/relics, potions.
- **I3 Presentation**: act themes/backgrounds, character & enemy animation, death/hit polish, glow, UI polish, per-card SFX.
- **I4 Meta**: ascension levels, unlockable 4th character, achievements, stats screen, daily seed run.
- **I5 Reach**: English/Japanese, gamepad, accessibility toggles (reduced flash/shake, hit-window assist, colour-safe UI), mobile perf pass.
- **I6 QA + packaging**: multi-style bots, per-character win-rate tuning, screen/event fuzz test, store page assets, README with screenshots.

## Status
- [x] I1 Onboarding + rhythm clarity (tutorial, early/late, lane marker)
- [x] I2 Combat depth (shooter/charger/splitter, 3 beat-patterned bosses, Fever, 27 cards, 18 relics, potions)
- [x] I3 Presentation (glow layer, death sprites, player anim, floor themes, card art, pitched PERFECT SFX, low-HP muffle)
- [x] I4 Meta (ascension, 4th character, achievements/records, daily run)
- [x] I5 Reach (EN/JA, gamepad, reduce-flash, timing assist)
- [x] I6 QA (human-like bot ~25% win at A0, fuzz via bots, enemy-flip rendering bug fixed, README/screenshots)

## Next ideas (I7+)
- Act 2 (new enemy set/boss, floors 11-20) and a 5th/6th character; more events (15+), relic synergies, curses.
- Per-track note-charts: enemy/boss attacks keyed to actual drum hits; more music + track select.
- Hand-made art pass (replace Kenney tiles with a unified custom style) and animated UI; shader glow/CRT option.
- Real-device mobile perf/latency pass; PWA install; leaderboard for Daily Run.
- Localisation of store page; trailer GIF; itch/Steam page copy.
