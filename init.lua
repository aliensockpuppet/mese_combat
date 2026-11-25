mese_combat = {}
local mc = mese_combat

local S = core.settings
local function num(key, def) return tonumber(S:get("mese_combat." .. key)) or def end

mc.cfg = {
	sprint_speed    = num("sprint_speed", 1.3),
	sprint_fov      = num("sprint_fov", 1.08),
	crit_multiplier = num("crit_multiplier", 1.5),
	full_charge     = num("full_charge", 0.9),
	kb_base         = num("kb_base", 5.5),
	kb_sprint       = num("kb_sprint", 3.5),
	kb_up           = num("kb_up", 4.0),
	mobs            = S:get_bool("mese_combat.mobs", true),
	mob_damage      = num("mob_damage", 1.0),
	kb_air_up       = 1.0,
	min_charge_mult = 0.2,
}

mc.weapons = {}
mc.foods = {}

mc.hand = { damage = 3, charge_time = 0.5, range = 3.0, kb_mult = 0.6 }

local function make_reg()
	local list = {}
	return list, function(fn) list[#list + 1] = fn end
end

mc.registered_on_punch_raw, mc.register_on_punch_raw = make_reg()

mc.registered_allow_hit, mc.register_allow_hit = make_reg()

mc.registered_on_hit, mc.register_on_hit = make_reg()

mc.registered_allow_eat, mc.register_allow_eat = make_reg()

mc.registered_on_eat, mc.register_on_eat = make_reg()

local state = {}

local function st(player)
	local name = player:get_player_name()
	local s = state[name]
	if not s then
		s = {
			physics = {},
			sprint_blocks = {},
			sprinting = false,
			reset_lock = false,
			last_attack_us = 0,
			last_eat_us = 0,
			wield = "",
		}
		state[name] = s
	end
	return s
end

core.register_on_leaveplayer(function(player)
	state[player:get_player_name()] = nil
end)

local function now() return core.get_us_time() end

local PHYS_FIELDS = {
	"speed", "speed_walk", "speed_climb", "speed_crouch", "speed_fast", "jump", "gravity",
	"acceleration_default", "acceleration_air", "acceleration_fast",
}

local function apply_physics(player)
	local s = st(player)
	local out = {}
	for _, f in ipairs(PHYS_FIELDS) do out[f] = 1 end
	for _, t in pairs(s.physics) do
		for _, f in ipairs(PHYS_FIELDS) do
			if t[f] then out[f] = out[f] * t[f] end
		end
	end
	player:set_physics_override(out)
end

function mc.set_physics(player, id, tbl)
	st(player).physics[id] = tbl
	apply_physics(player)
end

function mc.clear_physics(player, id)
	local s = st(player)
	if s.physics[id] then
		s.physics[id] = nil
		apply_physics(player)
	end
end

local function node_solid(pos)
	local node = core.get_node_or_nil(pos)
	if not node then return true end
	local def = core.registered_nodes[node.name]
	if not def then return true end
	return def.walkable ~= false or def.climbable == true
end

function mc.is_on_ground(player, depth)
	local pos = player:get_pos()
	local cb = player:get_properties().collisionbox
	local y = pos.y + cb[2] - (depth or 0.08)
	local e = 0.02
	for _, x in ipairs({ cb[1] + e, cb[4] - e }) do
		for _, z in ipairs({ cb[3] + e, cb[6] - e }) do
			if node_solid({ x = pos.x + x, y = y, z = pos.z + z }) then
				return true
			end
		end
	end
	return false
end

function mc.block_sprint(player, id, seconds)
	local s = st(player)
	s.sprint_blocks[id] = seconds and (now() + seconds * 1e6) or true
end

function mc.unblock_sprint(player, id)
	st(player).sprint_blocks[id] = nil
end

function mc.is_sprinting(player)
	local s = state[player:get_player_name()]
	return s ~= nil and s.sprinting
end

local function sprint_blocked(s, t)
	for id, v in pairs(s.sprint_blocks) do
		if v == true or v > t then
			return true
		end
		s.sprint_blocks[id] = nil
	end
	return false
end

local function set_sprint(player, s, on)
	if s.sprinting == on then return end
	s.sprinting = on
	if on then
		mc.set_physics(player, "mese_combat:sprint", { speed_walk = mc.cfg.sprint_speed })
		if mc.cfg.sprint_fov > 1 then player:set_fov(mc.cfg.sprint_fov, true, 0.15) end
	else
		mc.clear_physics(player, "mese_combat:sprint")
		if mc.cfg.sprint_fov > 1 then player:set_fov(0, true, 0.15) end
	end
end

function mc.stop_sprint(player, lock)
	local s = st(player)
	if lock then s.reset_lock = true end
	set_sprint(player, s, false)
end

core.register_globalstep(function()
	local t = now()
	for _, player in ipairs(core.get_connected_players()) do
		local s = st(player)
		local c = player:get_player_control()
		if s.reset_lock and (not c.aux1 or not c.up) then
			s.reset_lock = false
		end
		local want = c.aux1 and c.up and not c.sneak and not c.down
			and not s.reset_lock and not sprint_blocked(s, t)
		set_sprint(player, s, want)

		local w = player:get_wielded_item():get_name()
		if w ~= s.wield then
			s.wield = w
			s.last_attack_us = t
		end
	end
end)

function mc.register_weapon(name, itemdef, wdef)
	assert(wdef.damage and wdef.charge_time, "mese_combat: weapon needs damage and charge_time")
	wdef.range = wdef.range or 3.5
	wdef.kb_mult = wdef.kb_mult or 1
	itemdef.range = wdef.range
	itemdef.tool_capabilities = {
		full_punch_interval = wdef.charge_time,
		max_drop_level = 0,
		groupcaps = {},
		damage_groups = { fleshy = wdef.damage },
	}
	mc.weapons[name] = wdef
	core.register_tool(name, itemdef)
end

function mc.get_weapon(itemname)
	return mc.weapons[itemname] or mc.hand
end

function mc.get_charge(player)
	local s = st(player)
	local w = mc.get_weapon(player:get_wielded_item():get_name())
	return math.min(1, (now() - s.last_attack_us) / 1e6 / w.charge_time)
end

function mc.reset_charge(player)
	st(player).last_attack_us = now()
end

core.calculate_knockback = function() return 0 end

local function run_all(list, ...)
	for _, fn in ipairs(list) do fn(...) end
end

local function target_center(obj)
	local pos = obj:get_pos()
	local cb = obj:get_properties().collisionbox
	return vector.offset(pos, 0, cb[2] + (cb[5] - cb[2]) * 0.5, 0)
end

local function crit_particles(obj)
	local pos = target_center(obj)
	core.add_particlespawner({
		amount = 15, time = 0.1,
		minpos = vector.offset(pos, -0.5, -0.5, -0.5), maxpos = vector.offset(pos, 0.5, 0.5, 0.5),
		minvel = { x = -0.1, y = -0.1, z = -0.1 }, maxvel = { x = 0.1, y = 0.1, z = 0.1 },
		minexptime = 1, maxexptime = 2,
		minsize = 1.5, maxsize = 1.5,
		texture = "mese_combat_crit.png^[colorize:#bc7a57:127",
	})
end

function mc.apply_hit(hitter, target, opts)
	local w = mc.get_weapon(opts.weapon)
	local charge = math.max(0, math.min(1, opts.charge or 1))
	local full = charge >= mc.cfg.full_charge
	local mult = mc.cfg.min_charge_mult + (1 - mc.cfg.min_charge_mult) * charge * charge

	local hitter_air = not mc.is_on_ground(hitter)
	local crit = full and hitter_air and hitter:get_velocity().y < -0.3
	local sprint_hit = full and opts.sprinting == true

	local dmg = w.damage * mult * (opts.damage_mult or 1)
	if crit then dmg = dmg * mc.cfg.crit_multiplier end
	dmg = math.max(1, math.floor(dmg + 0.5))

	local dir = vector.subtract(target:get_pos(), hitter:get_pos())
	dir.y = 0
	dir = vector.length(dir) > 0 and vector.normalize(dir) or vector.new(0, 0, 0)
	local h = mc.cfg.kb_base * (0.4 + 0.6 * charge) * w.kb_mult
	if sprint_hit then h = h + mc.cfg.kb_sprint end
	local tv = target:get_velocity()
	local up = mc.is_on_ground(target) and mc.cfg.kb_up or mc.cfg.kb_air_up
	up = math.max(0, up - math.max(0, tv.y))
	local kb = vector.new(dir.x * h, up, dir.z * h)

	local info = { weapon = opts.weapon, wdef = w, damage = dmg, charge = charge,
		full = full, crit = crit, sprint_hit = sprint_hit, kb = kb, target_vel = tv }

	local tle = target:get_luaentity()
	if opts.take_hit then
		opts.take_hit(dmg, info)
	elseif tle and tle._mc_take_hit then
		tle:_mc_take_hit(dmg, hitter, info)
	else
		target:set_hp(target:get_hp() - dmg, { type = "punch", object = hitter })
	end
	if not opts.no_kb then target:add_velocity(kb) end

	if sprint_hit then
		if hitter:is_player() then
			mc.stop_sprint(hitter, true)
		else
			local hle = hitter:get_luaentity()
			if hle and hle._mc_sprint_hit then hle:_mc_sprint_hit() end
		end
	end
	if full and w.stagger then
		if target:is_player() then
			mc.set_physics(target, "mese_combat:stagger", { speed_walk = w.stagger.speed })
			mc.block_sprint(target, "mese_combat:stagger", w.stagger.time)
			mc.stop_sprint(target, false)
			local tname = target:get_player_name()
			core.after(w.stagger.time, function()
				local p = core.get_player_by_name(tname)
				if p then mc.clear_physics(p, "mese_combat:stagger") end
			end)
		elseif tle and tle._mc_stagger then
			tle:_mc_stagger(w.stagger)
		end
	end

	local tpos = target:get_pos()
	core.sound_play("mese_combat_hurt", { pos = tpos, gain = crit and 1.0 or 0.7,
		pitch = crit and 1.3 or 1.0, max_hear_distance = 24 }, true)
	if crit then crit_particles(target) end

	if full and w.on_full_hit then w.on_full_hit(hitter, target, info) end
	run_all(mc.registered_on_hit, hitter, target, info)
	return info
end

function mc.aimed_target(player, range)
	local pos = player:get_pos()
	local eye = vector.offset(pos, 0, player:get_properties().eye_height or 1.625, 0)
	local stop = vector.add(eye, vector.multiply(player:get_look_dir(), range))
	for pt in core.raycast(eye, stop, true, false) do
		if pt.type == "node" then return nil end
		if pt.type == "object" and pt.ref ~= player then
			local obj = pt.ref
			local le = obj:get_luaentity()
			if obj:is_player() or (le and le._mc_take_hit) then
				for _, fn in ipairs(mc.registered_allow_hit) do
					if fn(obj, player) == false then return nil end
				end
				return obj
			end
		end
	end
	return nil
end

function mc.player_hit(hitter, target, extra)
	local t = now()
	local hs = st(hitter)
	local weapon_name = hitter:get_wielded_item():get_name()
	local w = mc.get_weapon(weapon_name)
	local interval = (t - hs.last_attack_us) / 1e6

	run_all(mc.registered_on_punch_raw, target, hitter,
		{ weapon = weapon_name, wdef = w, interval = interval })

	for _, fn in ipairs(mc.registered_allow_hit) do
		if fn(target, hitter) == false then return false end
	end

	hs.last_attack_us = t
	local opts = { weapon = weapon_name, charge = interval / w.charge_time, sprinting = hs.sprinting }
	for k, v in pairs(extra or {}) do opts[k] = v end
	mc.apply_hit(hitter, target, opts)
	return true
end

-- A punch from a player who is out of weapon reach is a projectile (an arrow,
-- a thrown item). It keeps its own damage instead of becoming a melee hit.
function mc.is_melee(hitter, target)
	local w = mc.get_weapon(hitter:get_wielded_item():get_name())
	return vector.distance(hitter:get_pos(), target:get_pos()) <= (w.range or 3.5) + 1.5
end

core.register_on_punchplayer(function(target, hitter)
	if not hitter then return end
	if target:get_hp() <= 0 then return true end
	if hitter:is_player() and mc.is_melee(hitter, target) then
		mc.player_hit(hitter, target)
		return true
	end
	-- Mobs, projectiles and other hitters do their normal damage.
end)

local own_crits = core.global_exists("mcl_mobs")

local function wrap_entity(def)
	local orig = def.on_punch
	def.on_punch = function(self, puncher, tflp, caps, dir, damage, ...)
		local obj = self.object
		if not (puncher and puncher:is_player()) or self._mc_take_hit or self._mc_ignore
				or (obj:get_armor_groups().immortal or 0) > 0
				or not mc.weapons[puncher:get_wielded_item():get_name()] then
			if orig then return orig(self, puncher, tflp, caps, dir, damage, ...) end
			return
		end
		local ret = true
		mc.player_hit(puncher, obj, {
			damage_mult = mc.cfg.mob_damage,
			no_kb = orig ~= nil,
			take_hit = function(dmg, info)
				if not orig then
					obj:set_hp(obj:get_hp() - dmg, { type = "punch", object = puncher })
					return
				end
				if own_crits and info.crit then dmg = dmg / mc.cfg.crit_multiplier end
				ret = orig(self, puncher, 1, { full_punch_interval = 1, damage_groups = { fleshy = dmg } }, dir, dmg)
			end,
		})
		return ret
	end
end

core.register_on_mods_loaded(function()
	if not mc.cfg.mobs then return end
	for name, def in pairs(core.registered_entities) do
		if not name:find("^__builtin:") then wrap_entity(def) end
	end
end)

function mc.eat(itemstack, user, pointed_thing)
	if not user or not user:is_player() then return end
	local name = itemstack:get_name()
	local f = mc.foods[name]
	if not f or user:get_hp() <= 0 then return end

	if user:get_wielded_item():get_name() ~= name then return end
	local s = st(user)
	local t = now()
	if f.cooldown > 0 and t - s.last_eat_us < f.cooldown * 1e6 then return end
	for _, fn in ipairs(mc.registered_allow_eat) do
		if fn(user, name) == false then return end
	end
	s.last_eat_us = t
	if f.penalty then
		s.last_attack_us = t
		mc.stop_sprint(user, true)
	end
	local before = user:get_hp()
	local result = core.do_item_eat(f.heal, nil, itemstack, user, pointed_thing)
	run_all(mc.registered_on_eat, user, name, user:get_hp() - before)
	return result
end

function mc.register_food(name, itemdef, fdef)
	fdef = fdef or {}
	local f = {
		heal = fdef.heal or 25,
		use = fdef.use or "left",
		cooldown = fdef.cooldown or 0,
		penalty = fdef.penalty or false,
	}
	mc.foods[name] = f
	if f.use == "left" then
		itemdef.on_use = mc.eat
	else
		itemdef.on_secondary_use = mc.eat
		itemdef.on_place = mc.eat
	end
	core.register_craftitem(name, itemdef)
end

dofile(core.get_modpath("mese_combat") .. "/hud.lua")
