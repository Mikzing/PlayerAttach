-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
-- ┃  ____  _                         _   _          ┃
-- ┃ |  _ \| | __ _ _   _  ___ _ __ / \ | |_        ┃
-- ┃ | |_) | |/ _` | | | |/ _ \ '__/ _ \| __|       ┃
-- ┃ |  __/| | (_| | |_| |  __/ | / ___ \ |_        ┃
-- ┃ |_|   |_|\__,_|\__, |\___|_|/_/   \_\__|       ┃
-- ┃    _   _  _    |___/      _                     ┃
-- ┃   / \ | || |_ __ _  ___| |__                   ┃
-- ┃  / _ \| __| __/ _` |/ __| '_ \                 ┃
-- ┃ / ___ \ |_| || (_| | (__| | | |                ┃
-- ┃/_/   \_\__|\__\__,_|\___|_| |_|                ┃
-- ┃                                                 ┃
-- ┃              by Mikz                            ┃
-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
--
-- Player Attach v4.0.0 — Lexis Script
-- Attach yourself to any player's vehicle
--

local SCRIPT_NAME    = 'Player Attach'
local SCRIPT_VERSION = '4.0.0'

-- ─── Permission check ───────────────────────────────────────────────
local perm_ok, perm_val = pcall(function()
    return this.permissions() & permission.natives
end)
if not perm_ok or not perm_val or perm_val == 0 then
    pcall(notify.push, SCRIPT_NAME, 'Natives permission required.', { icon = notify.icon.hazard })
    pcall(this.unload)
    return
end

-- ─── Natives ────────────────────────────────────────────────────────
local N_ATTACH_ENTITY_TO_ENTITY             = 0x6B9BBD38AB0796DF
local N_DETACH_ENTITY                       = 0x961AC54BF0613F5D
local N_IS_ENTITY_ATTACHED                  = 0xB346476EF1A64897
local N_DOES_ENTITY_EXIST                   = 0x7239B21A38F536BA
local N_SET_PED_CAN_PLAY_AMBIENT_ANIMS      = 0x6EC47A344923E1ED
local N_SET_PED_CAN_PLAY_AMBIENT_BASE_ANIMS = 0x0EB0585D15254740

-- ─── Utilities ──────────────────────────────────────────────────────
local function call_native(hash, ...)
    local ok, r = pcall(invoker.call, hash, ...)
    return ok and r or nil
end

local function to_bool(r)
    if r == nil then return false end
    local t = type(r)
    if t == 'boolean' then return r end
    if t == 'number'  then return r ~= 0 end
    if t == 'table' then
        if r.bool ~= nil then return r.bool end
        if r.int  ~= nil then return r.int ~= 0 end
        return false
    end
    local ok, n = pcall(tonumber, r)
    return ok and n ~= nil and n ~= 0
end

local function safe_notify(text, opts)
    pcall(notify.push, SCRIPT_NAME, tostring(text), opts)
end

local function entity_exists(h)
    return h and h ~= 0 and to_bool(call_native(N_DOES_ENTITY_EXIST, h))
end

local function is_attached(e)
    return e and e ~= 0 and to_bool(call_native(N_IS_ENTITY_ATTACHED, e))
end

-- ─── Entity getters ─────────────────────────────────────────────────
local function get_my_ped()
    local ok, me = pcall(players.me)
    if not ok or not me then return nil end
    local ok2, ped = pcall(function() return me.ped end)
    return (ok2 and ped and ped ~= 0) and ped or nil
end

local function get_my_entity()
    local ok, me = pcall(players.me)
    if not ok or not me then return nil end
    local ok2, r = pcall(function()
        if me.in_vehicle and me.vehicle and me.vehicle ~= 0 then return me.vehicle end
        if me.ped and me.ped ~= 0 then return me.ped end
    end)
    return ok2 and r or nil
end

local function get_player_vehicle(pid)
    local ok, t = pcall(players.get, pid)
    if not ok or not t then return nil end
    local ok2, v = pcall(function()
        if t.in_vehicle and t.vehicle and t.vehicle ~= 0 then return t.vehicle end
    end)
    return ok2 and v or nil
end

-- Light check: player exists in session with a ped handle (no native calls)
local function player_has_ped(pid)
    local ok, t = pcall(players.get, pid)
    if not ok or not t then return false end
    local ok2, ped = pcall(function() return t.ped end)
    return ok2 and ped and ped ~= 0
end

-- ─── Ped idle freeze ────────────────────────────────────────────────
local function set_idle_anims(enabled)
    local ped = get_my_ped()
    if not ped then return end
    local v = enabled and 1 or 0
    call_native(N_SET_PED_CAN_PLAY_AMBIENT_ANIMS, ped, v)
    call_native(N_SET_PED_CAN_PLAY_AMBIENT_BASE_ANIMS, ped, v)
end

-- ─── Presets { name, tooltip, x, y, z, pitch, yaw } ────────────────
local presets = {
    { 'Roof',         'Stand on top of the vehicle',             0.0,   0.0,  1.2,  0.0,   0.0 },
    { 'Hood',         'Stand on the front hood',                 0.0,   2.5,  0.8,  0.0,   0.0 },
    { 'Trunk',        'Stand on the back trunk, facing rear',    0.0,  -2.5,  0.8,  0.0, 180.0 },
    { 'Left Side',    'Hang off the left side, facing outward', -1.2,   0.0,  0.5,  0.0, -90.0 },
    { 'Right Side',   'Hang off the right side, facing outward', 1.2,   0.0,  0.5,  0.0,  90.0 },
    { 'Hanging Back', 'Cling to the rear bumper',                0.0,  -2.0,  0.2,  0.0, 180.0 },
}

-- ─── Attachment state ───────────────────────────────────────────────
local attached_vehicle     = nil
local attached_player_name = nil
local offset = { x = 0.0, y = 0.0, z = 0.0, pitch = 0.0, yaw = 0.0 }

local attach_state = {
    active  = false,
    vehicle = nil,
    x = 0.0, y = 0.0, z = 0.0,
    pitch = 0.0, yaw = 0.0,
}

local function raw_attach(entity, veh, x, y, z, pitch, yaw)
    -- Rotation order: xRot(pitch), yRot(roll=0), zRot(yaw)
    -- useSoftPinning=0 so the game doesn't override our rotation
    call_native(N_ATTACH_ENTITY_TO_ENTITY,
        entity, veh, 0,
        x + 0.0, y + 0.0, z + 0.0,
        pitch + 0.0, 0.0, yaw + 0.0,
        0, 1, 0, 0, 2, 1)
end

local function do_attach(veh, x, y, z, pitch, yaw)
    local entity = get_my_entity()
    if not entity then safe_notify('Could not get your entity'); return false end

    if is_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    raw_attach(entity, veh, x, y, z, pitch, yaw)
    set_idle_anims(false)

    attached_vehicle     = veh
    attach_state.active  = true
    attach_state.vehicle = veh
    attach_state.x, attach_state.y, attach_state.z = x, y, z
    attach_state.pitch, attach_state.yaw = pitch, yaw
    return true
end

local function do_detach()
    attach_state.active  = false
    attach_state.vehicle = nil

    -- Always try to detach the entity, even if our state got out of sync
    local entity = get_my_entity()
    if entity then
        pcall(call_native, N_DETACH_ENTITY, entity, 1, 1)
    end

    set_idle_anims(true)
    attached_vehicle     = nil
    attached_player_name = nil
end

local function reattach()
    if not attached_vehicle then return end
    pcall(do_attach, attached_vehicle,
        offset.x, offset.y, offset.z,
        offset.pitch, offset.yaw)
end

-- ─── Re-attach thread ──────────────────────────────────────────────
util.create_thread(function()
    while true do
        util.yield(200)
        if not attach_state.active or not attach_state.vehicle then goto next end

        local entity = get_my_entity()
        if not entity then goto next end

        -- Only detach if the player left (not just out of streaming range)
        if attached_player_name then
            local still_here = false
            for pid, entry in pairs(player_entries) do
                if entry.name == attached_player_name and player_has_ped(pid) then
                    still_here = true
                    break
                end
            end
            if not still_here then
                attach_state.active  = false
                attach_state.vehicle = nil
                attached_vehicle     = nil
                attached_player_name = nil
                set_idle_anims(true)
                safe_notify('Player left — detached', { icon = notify.icon.hazard })
                goto next
            end
        end

        if not is_attached(entity) then
            raw_attach(entity, attach_state.vehicle,
                attach_state.x, attach_state.y, attach_state.z,
                attach_state.pitch, attach_state.yaw)
            set_idle_anims(false)
        end

        ::next::
    end
end)

-- ─── Menu root ──────────────────────────────────────────────────────
local root = menu.root()
if not root then
    safe_notify('Failed to get menu root.', { icon = notify.icon.hazard })
    pcall(this.unload)
    return
end

-- ─── Player tracking ────────────────────────────────────────────────
local player_entries = {}  -- pid → { menu, name, sliders }

local function safe_delete_menu(m)
    if not m then return end
    local ok = pcall(function() m:delete() end)
    if not ok then pcall(function() m:remove() end) end
end

-- ─── Sync sliders for a player entry ────────────────────────────────
local function sync_sliders(entry)
    if not entry or not entry.sliders then return end
    local sl = entry.sliders
    pcall(function() sl.x.value     = offset.x end)
    pcall(function() sl.y.value     = offset.y end)
    pcall(function() sl.z.value     = offset.z end)
    pcall(function() sl.pitch.value = offset.pitch end)
    pcall(function() sl.yaw.value   = offset.yaw end)
end

-- ─── Build position controls inside a parent menu ───────────────────
local function build_position_controls(parent)
    -- Try sliders first
    local sliders = {}
    local slider_defs = {
        { 'X  Left / Right', 'x',     -10.0,  10.0, 0.05, '%.2f', 'Move left (-) or right (+)' },
        { 'Y  Back / Front', 'y',     -10.0,  10.0, 0.05, '%.2f', 'Move backward (-) or forward (+)' },
        { 'Z  Down / Up',    'z',     -10.0,  10.0, 0.05, '%.2f', 'Move down (-) or up (+)' },
        { 'Pitch',           'pitch', -180.0, 180.0, 1.0, '%.0f', 'Tilt forward/backward (nod)' },
        { 'Yaw',             'yaw',   -180.0, 180.0, 1.0, '%.0f', 'Rotate left/right (turn)' },
    }

    local slider_count = 0
    for _, d in ipairs(slider_defs) do
        local label, key, lo, hi, step, fmt, tip = d[1], d[2], d[3], d[4], d[5], d[6], d[7]
        local ok, s = pcall(function()
            local sl = parent:number_float(label, menu.type.scroll)
            sl:fmt(fmt, lo, hi, step)
            sl:tooltip(tip)
            sl:event(menu.event.click, function(opt)
                offset[key] = opt.value
                reattach()
            end)
            return sl
        end)
        if ok and s then
            sliders[key] = s
            slider_count = slider_count + 1
        end
    end

    -- If at least position sliders worked, use them
    if slider_count >= 3 then
        local rst = parent:button('Reset Position')
        rst:tooltip('Reset all offsets back to 0')
        rst:event(menu.event.click, function()
            offset.x, offset.y, offset.z = 0.0, 0.0, 0.0
            offset.pitch, offset.yaw = 0.0, 0.0
            for _, key in ipairs({ 'x', 'y', 'z', 'pitch', 'yaw' }) do
                if sliders[key] then pcall(function() sliders[key].value = 0.0 end) end
            end
            reattach()
            safe_notify('Position reset')
        end)
        return sliders
    end

    -- Sliders failed — clean up any that succeeded
    for _, s in pairs(sliders) do
        pcall(function() s:delete() end)
    end

    -- Button-based fallback (finer default steps)
    local step_sizes = { 0.01, 0.025, 0.05, 0.1, 0.25 }
    local step_names = { '0.01', '0.025', '0.05', '0.1', '0.25' }
    local rot_steps  = { 0.5, 1.0, 5.0, 15.0, 30.0 }
    local rot_names  = { '0.5', '1', '5', '15', '30' }
    local step_idx   = 3

    local cyc = parent:button('Cycle Step Size [0.05]')
    cyc:tooltip('Click to cycle: 0.01 / 0.025 / 0.05 / 0.1 / 0.25')
    cyc:event(menu.event.click, function()
        step_idx = step_idx % 5 + 1
        pcall(function() cyc:name('Cycle Step Size [' .. step_names[step_idx] .. ']') end)
        safe_notify('Step: ' .. step_names[step_idx] .. '  Rot: ' .. rot_names[step_idx])
    end)

    local axes = {
        { 'x',     '< Left',      'Right >',     false, 'Move left',          'Move right' },
        { 'y',     '< Back',      'Front >',     false, 'Move backward',      'Move forward' },
        { 'z',     '< Down',      'Up >',        false, 'Move down',          'Move up' },
        { 'pitch', '< Pitch Down','Pitch Up >',  true,  'Tilt forward',       'Tilt backward' },
        { 'yaw',   '< Yaw Left',  'Yaw Right >', true,  'Turn left',          'Turn right' },
    }
    for _, a in ipairs(axes) do
        local key, lbl_neg, lbl_pos, is_rot, tip_neg, tip_pos = a[1], a[2], a[3], a[4], a[5], a[6]
        local bn = parent:button(lbl_neg)
        bn:tooltip(tip_neg)
        bn:event(menu.event.click, function()
            local s = is_rot and rot_steps[step_idx] or step_sizes[step_idx]
            offset[key] = offset[key] - s
            reattach()
            safe_notify(key .. ' = ' .. string.format('%.2f', offset[key]))
        end)
        local bp = parent:button(lbl_pos)
        bp:tooltip(tip_pos)
        bp:event(menu.event.click, function()
            local s = is_rot and rot_steps[step_idx] or step_sizes[step_idx]
            offset[key] = offset[key] + s
            reattach()
            safe_notify(key .. ' = ' .. string.format('%.2f', offset[key]))
        end)
    end

    local rst = parent:button('Reset Position')
    rst:tooltip('Reset all offsets back to 0')
    rst:event(menu.event.click, function()
        offset.x, offset.y, offset.z = 0.0, 0.0, 0.0
        offset.pitch, offset.yaw = 0.0, 0.0
        reattach()
        safe_notify('Position reset')
    end)

    return nil
end

-- ─── Per-player submenu ─────────────────────────────────────────────
local function create_player_menu(pid, pname)
    local p_menu = root:submenu(pname)
    if not p_menu then return false end

    local entry = { menu = p_menu, name = pname, sliders = nil }
    player_entries[pid] = entry

    -- Attach with current offset
    local att = p_menu:button('Attach')
    att:tooltip('Attach to ' .. pname .. ' using current position offsets')
    att:event(menu.event.click, function()
        local veh = get_player_vehicle(pid)
        if not veh then safe_notify(pname .. ' is not in a vehicle'); return end
        if do_attach(veh, offset.x, offset.y, offset.z, offset.pitch, offset.yaw) then
            attached_player_name = pname
            safe_notify('Attached to ' .. pname)
        end
    end)

    -- Detach
    local det = p_menu:button('Detach')
    det:tooltip('Detach from ' .. pname)
    det:event(menu.event.click, function()
        do_detach()
        safe_notify('Detached from ' .. pname)
    end)

    -- Presets sub-submenu
    local presets_sub = p_menu:submenu('Presets')
    if presets_sub then
        presets_sub:tooltip('Quick-attach to common positions on the vehicle')
        for _, p in ipairs(presets) do
            local btn = presets_sub:button(p[1])
            btn:tooltip(p[2])
            btn:event(menu.event.click, function()
                local veh = get_player_vehicle(pid)
                if not veh then safe_notify(pname .. ' is not in a vehicle'); return end

                offset.x, offset.y, offset.z = p[3], p[4], p[5]
                offset.pitch, offset.yaw = p[6], p[7]
                sync_sliders(entry)

                if do_attach(veh, p[3], p[4], p[5], p[6], p[7]) then
                    attached_player_name = pname
                    safe_notify('Attached to ' .. pname .. ' (' .. p[1] .. ')')
                end
            end)
        end
    end

    -- Adjust Position sub-submenu
    local pos_sub = p_menu:submenu('Adjust Position')
    if pos_sub then
        pos_sub:tooltip('Fine-tune your X/Y/Z position and rotation on the vehicle')
        entry.sliders = build_position_controls(pos_sub)
    end

    return true
end

-- ─── Player list management ─────────────────────────────────────────
local function remove_player(pid)
    local entry = player_entries[pid]
    if not entry then return end
    safe_delete_menu(entry.menu)
    player_entries[pid] = nil
end

local function refresh_players()
    local ok, player_list = pcall(players.list)
    if not ok or not player_list then safe_notify('Could not get player list'); return end

    local ok_me, my = pcall(players.me)
    local my_id = -1
    if ok_me and my then
        local ok_id, v = pcall(function() return my.id end)
        if ok_id and v then my_id = v end
    end

    -- All IDs currently in the session
    local session_ids = {}
    for _, p in ipairs(player_list) do
        local p_ok, p_id = pcall(function() return p.id end)
        if p_ok and p_id and p_id ~= my_id then session_ids[p_id] = true end
    end

    -- Remove departed players (collect first to avoid modifying table during iteration)
    local to_remove = {}
    for pid, entry in pairs(player_entries) do
        if not session_ids[pid] then
            to_remove[#to_remove + 1] = pid
            if attached_player_name and entry.name == attached_player_name then
                do_detach()
                safe_notify(entry.name .. ' left — detached', { icon = notify.icon.hazard })
            end
        end
    end
    for _, pid in ipairs(to_remove) do
        remove_player(pid)
    end

    -- Build a set of names already in the menu (catches orphaned entries
    -- where safe_delete_menu failed but the pid was removed from the table)
    local existing_names = {}
    for _, entry in pairs(player_entries) do
        existing_names[entry.name] = true
    end

    -- Add new players
    for _, p in ipairs(player_list) do
        local p_ok, p_id, p_name = pcall(function() return p.id, p.name end)
        if p_ok and p_id and p_id ~= my_id and p_name then
            local name = tostring(p_name)
            if #name > 0 and not player_entries[p_id] and not existing_names[name] and player_has_ped(p_id) then
                pcall(create_player_menu, p_id, name)
                existing_names[name] = true
            end
        end
    end

    local total = 0
    for _ in pairs(player_entries) do total = total + 1 end
    safe_notify('Players: ' .. total)
end

-- ─── Quick Detach ───────────────────────────────────────────────────
local det_btn = root:button('Detach')
det_btn:tooltip('Quick detach from any vehicle you are attached to')
det_btn:event(menu.event.click, function()
    local name = attached_player_name or 'vehicle'
    do_detach()
    safe_notify('Detached from ' .. name)
end)

-- ─── Refresh Players ────────────────────────────────────────────────
local refresh_requested = false

local ref_btn = root:button('Refresh Players')
ref_btn:tooltip('Scan the session for players and update the list')
ref_btn:event(menu.event.click, function()
    refresh_requested = true
end)

util.create_thread(function()
    while true do
        util.yield(250)
        if refresh_requested then
            refresh_requested = false
            pcall(refresh_players)
        end
    end
end)

-- ─── Cleanup thread ────────────────────────────────────────────────
util.create_thread(function()
    while true do
        util.yield(5000)
        local to_remove = {}
        for pid, entry in pairs(player_entries) do
            if not player_has_ped(pid) then
                to_remove[#to_remove + 1] = pid
                if attached_player_name and entry.name == attached_player_name then
                    do_detach()
                    safe_notify(entry.name .. ' left — detached', { icon = notify.icon.hazard })
                end
            end
        end
        for _, pid in ipairs(to_remove) do
            remove_player(pid)
        end
    end
end)

-- ─── Ready ──────────────────────────────────────────────────────────
safe_notify('v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
