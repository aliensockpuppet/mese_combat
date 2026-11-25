local mc = mese_combat
if not core.settings:get_bool("mese_combat.hud", true) then return end

local BAR_W, BAR_H, BAR_Y = 28, 2, 16
local STEPS = 10
local huds = {}
local off = {}

local function H(player)
	local name = player:get_player_name()
	local h = huds[name]
	if h then return h end
	h = {}
	h.bg = player:hud_add({
		type = "image", position = { x = 0.5, y = 0.5 }, offset = { x = -BAR_W / 2, y = BAR_Y },
		alignment = { x = 1, y = 0 }, scale = { x = 0, y = BAR_H }, text = "[fill:1x1:#00000066", z_index = 30,
	})
	h.fg = player:hud_add({
		type = "image", position = { x = 0.5, y = 0.5 }, offset = { x = -BAR_W / 2, y = BAR_Y },
		alignment = { x = 1, y = 0 }, scale = { x = 0, y = BAR_H }, text = "[fill:1x1:#ffffffcc", z_index = 31,
	})
	h.dmg = player:hud_add({
		type = "text", position = { x = 0.5, y = 0.5 }, offset = { x = 14, y = -12 },
		alignment = { x = 1, y = 0 }, number = 0xFFFFFF, text = "", z_index = 32,
	})
	h.combo = player:hud_add({
		type = "text", position = { x = 0.5, y = 0.5 }, offset = { x = 0, y = 30 },
		alignment = { x = 0, y = 0 }, number = 0xE6C34A, text = "", z_index = 32,
	})
	h.bar, h.dmg_until, h.combo_until = -1, 0, 0
	huds[name] = h
	return h
end

local function clear(player, h)
	player:hud_change(h.bg, "scale", { x = 0, y = BAR_H })
	player:hud_change(h.fg, "scale", { x = 0, y = BAR_H })
	player:hud_change(h.dmg, "text", "")
	player:hud_change(h.combo, "text", "")
	h.bar, h.dmg_until, h.combo_until = 0, 0, 0
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	off[name] = player:get_meta():get_string("mese_combat:hud") == "off" or nil
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	huds[name], off[name] = nil, nil
end)

core.register_globalstep(function()
	local t = core.get_us_time()
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		if not off[name] then
			local h = H(player)
			local w = mc.weapons[player:get_wielded_item():get_name()]

			local step = 0
			if w then
				local c = mc.get_charge(player)
				if c < 1 then
					step = math.max(1, math.min(STEPS - 1, math.floor(c * STEPS)))
				elseif mc.aimed_target(player, w.range) then
					step = STEPS + 1
				end
			end
			if step ~= h.bar then
				local was_ready = h.bar == STEPS + 1
				h.bar = step
				local show, ready = step > 0, step == STEPS + 1
				player:hud_change(h.bg, "scale", { x = show and BAR_W or 0, y = BAR_H })
				player:hud_change(h.fg, "scale", { x = ready and BAR_W or (show and math.floor(BAR_W * step / STEPS)) or 0, y = BAR_H })
				if ready ~= was_ready then
					player:hud_change(h.fg, "text", ready and "[fill:1x1:#ffd84a" or "[fill:1x1:#ffffffcc")
				end
			end
			if h.dmg_until > 0 and t > h.dmg_until then
				h.dmg_until = 0
				player:hud_change(h.dmg, "text", "")
			end
			if h.combo_until > 0 and t > h.combo_until then
				h.combo_until = 0
				player:hud_change(h.combo, "text", "")
			end
		end
	end
end)

local combo = {}

mc.register_on_hit(function(attacker, target, info)
	local t = core.get_us_time()

	if target:is_player() then
		local tn = target:get_player_name()
		combo[tn] = nil
		local th = huds[tn]
		if th and th.combo_until > 0 then
			th.combo_until = 0
			target:hud_change(th.combo, "text", "")
		end
	end
	if not attacker:is_player() then return end
	local an = attacker:get_player_name()
	local tid = target:is_player() and target:get_player_name() or tostring(target)

	local c = combo[an]
	if not c or c.target ~= tid or t - c.last > 3e6 then c = { target = tid, n = 0 } combo[an] = c end
	c.last = t
	if info.full then c.n = c.n + 1 end

	if off[an] then return end
	local h = H(attacker)
	local color = 0xFFFFFF
	if not info.full then color = 0x9A9A9A
	elseif info.crit then color = 0xFFD84A
	elseif info.sprint_hit then color = 0x7FD3FF end
	attacker:hud_change(h.dmg, "number", color)
	attacker:hud_change(h.dmg, "text", tostring(info.damage))
	h.dmg_until = t + 0.5e6
	if c.n >= 3 then
		attacker:hud_change(h.combo, "text", c.n .. " combo")
		h.combo_until = t + 1.5e6
	end
end)

core.register_on_leaveplayer(function(player) combo[player:get_player_name()] = nil end)

core.register_chatcommand("indicators", {
	params = "[on|off]",
	description = "Show or hide the charge bar, damage numbers, and combo counter",
	func = function(name, param)
		local p = core.get_player_by_name(name)
		if not p then return false end
		if param == "off" then
			off[name] = true
			p:get_meta():set_string("mese_combat:hud", "off")
			if huds[name] then clear(p, huds[name]) end
		elseif param == "on" then
			off[name] = nil
			p:get_meta():set_string("mese_combat:hud", "")
		end
		return true, "Indicators are " .. (off[name] and "off" or "on") .. "."
	end,
})
