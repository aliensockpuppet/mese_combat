# MESE Combat

Melee PvP combat for Luanti. Server-side only, players don't need to install anything.

Made for the MESE PVP server, but it doesn't depend on it. Needs Luanti 5.17+.

## Mechanics

- **Charge.** Every weapon has a charge time. Damage is `20% + 80% × charge²`, so a half-charged hit does about 40%. Switching items resets it. Spam clicking doesn't work.
- **Sprint.** Hold Aux1 (E by default) while walking forward. 1.3× speed and a small FOV change.
- **Sprint hits.** A full hit while sprinting does extra knockback and stops your sprint. Let go of E or W to sprint again. Same idea as W-tapping.
- **Crits.** A full hit while falling does 1.5× damage. The server checks that you're actually in the air.
- **Knockback.** Scales with charge, with a small lift if the target is on the ground. The engine's own knockback is turned off.
- **Stagger.** Weapons can have one. In MESE PVP, a full axe hit slows the target to 75% and blocks their sprint for 1 second.
- **Food.** Default is Minetest Game style: left-click, instant heal, no cooldown. Cooldown, right-click eating and a charge/sprint penalty can be set per food.

## Mobs

Hits on mobs with a `mese_combat` weapon use the same charge, crits and sprint hits. Works with any mob mod (Mobs Redo, Mineclonia/VoxeLibre mobs, and others): the mob's own `on_punch` still handles health, death, drops and knockback, it just gets the damage as a full-strength hit. Mobs with no `on_punch` take the damage and get knocked back by this mod.

Items that aren't registered with `mese_combat` hit mobs the normal way. Immortal entities are left alone, and an entity can opt out with `_mc_ignore = true`. Mobs hitting players also work the normal way: only player melee goes through the combat system.

Projectiles are left alone too. A punch from a player who is farther away than their weapon's reach (plus 1.5) counts as a projectile, like an arrow, and keeps its own damage. Other mods can ask with `mese_combat.is_melee(hitter, target)`.

Turn it off with `mese_combat.mobs = false`. If your weapons are tuned for players with a lot of HP, lower `mese_combat.mob_damage`.

## HUD

- Charge bar under the crosshair. It stays up in yellow when it's full and you're aiming at someone you can hit.
- Damage numbers: grey for weak hits, white for full, cyan for sprint hits, yellow for crits.
- Combo counter: full hits in a row on the same target without getting hit back.
- Crit particles.

Players can hide it with `/indicators off`. `mese_combat.hud = false` turns it off for everyone.

## MESE PVP numbers

100 HP per player.

| Item | Full hit | Charge | Reach |
|---|---|---|---|
| Sword | 14 (crit 21) | 0.65 s | 3.5 |
| Axe | 22 (crit 33), stagger | 1.1 s | 3.3 |
| Bread | heals 25 | none | |

Sword has more DPS, axe has bigger hits and the stagger.

## Settings

| Setting | Default | |
|---|---|---|
| `mese_combat.sprint_speed` | 1.3 | Sprint speed multiplier |
| `mese_combat.sprint_fov` | 1.08 | FOV multiplier while sprinting |
| `mese_combat.crit_multiplier` | 1.5 | Crit damage |
| `mese_combat.full_charge` | 0.9 | How charged a hit has to be to count as full |
| `mese_combat.kb_base` | 5.5 | Knockback on a full hit |
| `mese_combat.kb_sprint` | 3.5 | Extra knockback on a sprint hit |
| `mese_combat.kb_up` | 4.0 | Upward knockback |
| `mese_combat.hud` | true | HUD on or off |
| `mese_combat.mobs` | true | Combat system on mobs |
| `mese_combat.mob_damage` | 1.0 | Damage multiplier on mobs |

## API

```lua
mese_combat.register_weapon("mymod:sword", itemdef, {
	damage = 14,        -- at full charge
	charge_time = 0.6,  -- seconds
	range = 3.5,
	kb_mult = 1.0,
	stagger = { time = 1.0, speed = 0.75 },            -- optional
	on_full_hit = function(attacker, target, info) end, -- optional
})

mese_combat.register_food("mymod:bread", itemdef, {
	heal = 25,
	use = "left",      -- or "right"
	cooldown = 0,
	penalty = false,   -- true: eating resets charge and ends sprint
})

-- Callbacks
mese_combat.register_allow_hit(function(target, hitter) end)   -- return false to cancel
mese_combat.register_damage_modifier(function(hitter, target, damage, opts) end) -- return new damage
mese_combat.register_on_hit(function(attacker, target, info) end)
	-- info: weapon, damage, charge, full, crit, sprint_hit, kb
mese_combat.register_on_punch_raw(function(target, hitter, info) end) -- every punch (anticheat)
mese_combat.register_allow_eat(function(player, itemname) end)
mese_combat.register_on_eat(function(player, itemname, healed) end)

-- Physics: each mod sets its own multipliers under an id, so they don't overwrite each other
mese_combat.set_physics(player, "mymod:slow", { speed_walk = 0.5 })
mese_combat.clear_physics(player, "mymod:slow")

-- Sprint and charge
mese_combat.is_sprinting(player)
mese_combat.block_sprint(player, id, seconds)  -- nil = until unblocked
mese_combat.unblock_sprint(player, id)
mese_combat.stop_sprint(player, lock)
mese_combat.get_charge(player)                 -- 0..1
mese_combat.reset_charge(player)
mese_combat.is_on_ground(player)

-- Hits from non-players (bots, NPCs) using the same rules
mese_combat.apply_hit(attacker, target, { weapon = "mymod:sword", charge = 1, sprinting = false })
mese_combat.player_hit(player, target)         -- a player's hit, with charge from their attack timer
mese_combat.aimed_target(player, range)        -- what the player is aiming at, or nil
```

An entity can handle hits itself by defining these (the practice bots in MESE PVP do):

```lua
_mc_take_hit = function(self, damage, hitter, info) end, -- instead of losing HP
_mc_stagger = function(self, stagger) end,              -- stagger = { time =, speed = }
_mc_sprint_hit = function(self) end,                    -- it landed a sprint hit
```

Use `set_physics` instead of calling `set_physics_override` yourself, or mods will overwrite each other's speed changes.

## License

Code is MIT. Media is CC BY-SA, see `LICENSE-MEDIA.md` (sound from Minetest Game, crit texture from Mineclonia).
