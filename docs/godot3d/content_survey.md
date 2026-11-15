# Content numbers still in code (Stage 7 survey, dev.45)

Order to move them, biggest win first:

1. **5v5 store and rules** (`src/modes/tactical_shop.gd`: economy :21-33,
   ITEMS :40 (24), RULES :69 (6), KILL_REWARD :124, DAMAGE :158, BLAST_*
   :185-189, MOVE_SPREAD :194 + still/run/air/scope/crouch, REACH :213,
   FALLOFF :225, BOT_ORDER :531) with the 5v5 timings (tactical_mode.gd
   :30-39, bomb_mode.gd :18-25, hostage_mode.gd :13-26, modes.gd TAGTEAM
   :84-86, mode_feature.gd defaults :80-89). No data at all yet.
2. **Weapon hit numbers into weapons.cfg**: hit_zones.gd HEAD :47,
   MORE_REACTIONS :32, enemies.gd REACTIONS :60 / LUCKY_CHANCE :52,
   game_state.gd AMMO :74.
3. **One difficulty table**: game_world.gd configure() :41-43 (incoming,
   sharpness, ammo_scale), variants.gd EVERY :31, squad.gd SEARCH/SNEAK_STUN,
   squad_feature.gd :14-30, boss_fight.gd BACKUP :32, tactical_bot.gd :27-47.
4. **Bosses**: boss_kit.gd MAD_AT/DESPERATE_AT :35-36, STAGGER :40; each
   src/bosses/*.gd const block; mothership.gd :47-66; boss_arena.gd :30-51;
   boss_arenas.gd :30-53; boss_rematch.gd PAR :37. Many inline literals.
5. **County leftovers** into county.json: county_build.gd WEIGHTS :11,
   SWAP_CHANCE :13; county_coop.gd :18-24; county_moves.gd :14-18 (+inline);
   county_orbs.gd :15-23; county_data.gd MAP_IDS :11.
6. **Co-op SCALE** (coop_mode.gd :24-37), deathmatch limits
   (deathmatch_mode.gd :17-20), NetPlay LOBBY_ROWS/MATCH_ROWS (net_play.gd
   :53, :59), tactical_screens.gd MATCH_LENGTHS/TAG_LENGTHS.

Already data: county.json (maps, pools, xp, spawn, weapons, upgrades, perks,
milestones, card text); enemies.cfg (boss HP/speed/reach, variants' tint,
stumble, swap, tough_for); level casts in data/<level>.json.
