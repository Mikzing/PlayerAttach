--
-- ██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗
-- ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗
-- ██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝
-- ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗
-- ██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║
-- ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
--  █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗
-- ██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║  ██║
-- ███████║   ██║      ██║   ███████║██║     ███████║
-- ██╔══██║   ██║      ██║   ██╔══██║██║     ██╔══██║
-- ██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██║
-- ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
--
-- Player Attach v3.6.0 — Lexis Mod Menu Script
-- Attach your ped or vehicle to another player's vehicle
--

local SCRIPT_NAME    = 'Player Attach'
local SCRIPT_VERSION = '3.6.0'

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

local function is_valid_player(pid)
    local ok, t = pcall(players.get, pid)
    if not ok or not t then return false end
    local ok2, ped = pcall(function() return t.ped end)
    return ok2 and ped and ped ~= 0 and entity_exists(ped)
end

-- ─── Ped idle freeze ────────────────────────────────────────────────
local function set_idle_anims(enabled)
    local ped = get_my_ped()
    if not ped then return end
    local v = enabled and 1 or 0
    call_native(N_SET_PED_CAN_PLAY_AMBIENT_ANIMS, ped, v)
    call_native(N_SET_PED_CAN_PLAY_AMBIENT_BASE_ANIMS, ped, v)
end

-- ─── Presets ────────────────────────────────────────────────────────
local presets = {
    { 'Roof',         0.0,   0.0,  1.2,  0.0, 0.0,   0.0 },
    { 'Hood',         0.0,   2.5,  0.8,  0.0, 0.0,   0.0 },
    { 'Trunk',        0.0,  -2.5,  0.8,  0.0, 0.0, 180.0 },
    { 'Left Side',   -1.2,   0.0,  0.5,  0.0, 0.0, -90.0 },
    { 'Right Side',   1.2,   0.0,  0.5,  0.0, 0.0,  90.0 },
    { 'Hanging Back', 0.0,  -2.0,  0.2,  0.0, 0.0, 180.0 },
}

-- ─── Attachment state ───────────────────────────────────────────────
local attached_vehicle     = nil
local attached_player_name = nil
local offset = { x = 0.0, y = 0.0, z = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 }

local attach_state = {
    active  = false,
    vehicle = nil,
    x = 0.0, y = 0.0, z = 0.0,
    pitch = 0.0, roll = 0.0, yaw = 0.0,
}

local function raw_attach(entity, veh, x, y, z, pitch, roll, yaw)
    call_native(N_ATTACH_ENTITY_TO_ENTITY,
        entity, veh, 0,
        x + 0.0, y + 0.0, z + 0.0,
        pitch + 0.0, roll + 0.0, yaw + 0.0,
        0, 1, 1, 0, 2, 1)
end

local function do_attach(veh, x, y, z, pitch, roll, yaw)
    local entity = get_my_entity()
    if not entity then safe_notify('Could not get your entity'); return false end
    if not entity_exists(veh) then safe_notify('Target vehicle no longer exists'); return false end

    if is_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    raw_attach(entity, veh, x, y, z, pitch, roll, yaw)
    set_idle_anims(false)

    attached_vehicle     = veh
    attach_state.active  = true
    attach_state.vehicle = veh
    attach_state.x, attach_state.y, attach_state.z = x, y, z
    attach_state.pitch, attach_state.roll, attach_state.yaw = pitch, roll, yaw
    return true
end

local function do_detach()
    attach_state.active  = false
    attach_state.vehicle = nil

    local entity = get_my_entity()
    if entity and is_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    set_idle_anims(true)
    attached_vehicle     = nil
    attached_player_name = nil
end

local function reattach()
    if not attached_vehicle then return end
    pcall(do_attach, attached_vehicle,
        offset.x, offset.y, offset.z,
        offset.pitch, offset.roll, offset.yaw)
end

-- ─── Re-attach thread ──────────────────────────────────────────────
util.create_thread(function()
    while true do
        util.yield(200)
        if not attach_state.active or not attach_state.vehicle then goto next end

        local entity = get_my_entity()
        if not entity then goto next end

        if not entity_exists(attach_state.vehicle) then
            attach_state.active  = false
            attach_state.vehicle = nil
            attached_vehicle     = nil
            attached_player_name = nil
            set_idle_anims(true)
            safe_notify('Vehicle gone — detached', { icon = notify.icon.hazard })
            goto next
        end

        if not is_attached(entity) then
            raw_attach(entity, attach_state.vehicle,
                attach_state.x, attach_state.y, attach_state.z,
                attach_state.pitch, attach_state.roll, attach_state.yaw)
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

-- ─── Probe slider support once ──────────────────────────────────────
local use_sliders = false
do
    local probe_menu = root:submenu('_probe')
    if probe_menu then
        local ok, s = pcall(function()
            local sl = probe_menu:number_float('_test', menu.type.scroll)
            sl:fmt('%.2f', -1.0, 1.0, 0.1)
            return sl
        end)
        if ok and s then
            use_sliders = true
            pcall(function() s:delete() end)
        end
        pcall(function() probe_menu:delete() end)
    end
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
    pcall(function() sl.roll.value  = offset.roll end)
    pcall(function() sl.yaw.value   = offset.yaw end)
end

-- ─── Build position controls inside a parent menu ───────────────────
local function build_position_controls(parent)
    local sliders = nil

    if use_sliders then
        sliders = {}
        local defs = {
            { 'Left / Right', 'x',     -10.0,  10.0, 0.10, '%.2f' },
            { 'Back / Front', 'y',     -10.0,  10.0, 0.10, '%.2f' },
            { 'Down / Up',    'z',     -10.0,  10.0, 0.10, '%.2f' },
            { 'Pitch',        'pitch', -180.0, 180.0, 1.0, '%.0f' },
            { 'Roll',         'roll',  -180.0, 180.0, 1.0, '%.0f' },
            { 'Yaw',          'yaw',   -180.0, 180.0, 1.0, '%.0f' },
        }
        for _, d in ipairs(defs) do
            local label, key, lo, hi, step, fmt = d[1], d[2], d[3], d[4], d[5], d[6]
            local ok, s = pcall(function()
                local sl = parent:number_float(label, menu.type.scroll)
                sl:fmt(fmt, lo, hi, step)
                sl:event(menu.event.click, function(opt)
                    offset[key] = opt.value
                    reattach()
                end)
                return sl
            end)
            if ok and s then
                sliders[key] = s
            end
        end
    else
        local step_sizes = { 0.05, 0.1, 0.25, 0.5, 1.0 }
        local step_names = { '0.05', '0.1', '0.25', '0.5', '1.0' }
        local rot_steps  = { 1.0, 5.0, 15.0, 30.0, 45.0 }
        local rot_names  = { '1', '5', '15', '30', '45' }
        local step_idx   = 2

        parent:button('Cycle Step Size'):event(menu.event.click, function()
            step_idx = step_idx % 5 + 1
            safe_notify('Step: ' .. step_names[step_idx] .. '  Rot: ' .. rot_names[step_idx])
        end)

        local axes = {
            { 'x',     'Left',       'Right',      false },
            { 'y',     'Back',       'Front',      false },
            { 'z',     'Down',       'Up',         false },
            { 'pitch', 'Pitch Down', 'Pitch Up',   true  },
            { 'roll',  'Roll Left',  'Roll Right',  true  },
            { 'yaw',   'Yaw Left',   'Yaw Right',   true  },
        }
        for _, a in ipairs(axes) do
            local key, lbl_neg, lbl_pos, is_rot = a[1], a[2], a[3], a[4]
            parent:button(lbl_neg):event(menu.event.click, function()
                local s = is_rot and rot_steps[step_idx] or step_sizes[step_idx]
                offset[key] = offset[key] - s
                reattach()
                safe_notify(key .. ' = ' .. string.format('%.2f', offset[key]))
            end)
            parent:button(lbl_pos):event(menu.event.click, function()
                local s = is_rot and rot_steps[step_idx] or step_sizes[step_idx]
                offset[key] = offset[key] + s
                reattach()
                safe_notify(key .. ' = ' .. string.format('%.2f', offset[key]))
            end)
        end
    end

    parent:button('Reset Position'):event(menu.event.click, function()
        offset.x, offset.y, offset.z = 0.0, 0.0, 0.0
        offset.pitch, offset.roll, offset.yaw = 0.0, 0.0, 0.0
        if sliders then
            for _, key in ipairs({ 'x', 'y', 'z', 'pitch', 'roll', 'yaw' }) do
                if sliders[key] then pcall(function() sliders[key].value = 0.0 end) end
            end
        end
        reattach()
        safe_notify('Position reset')
    end)

    return sliders
end

-- ─── Per-player submenu ─────────────────────────────────────────────
local function create_player_menu(pid, pname)
    local p_menu = root:submenu(pname)
    if not p_menu then return false end

    local entry = { menu = p_menu, name = pname, sliders = nil }
    player_entries[pid] = entry

    -- Presets
    for _, p in ipairs(presets) do
        p_menu:button(p[1]):event(menu.event.click, function()
            local veh = get_player_vehicle(pid)
            if not veh then safe_notify(pname .. ' is not in a vehicle'); return end

            offset.x, offset.y, offset.z = p[2], p[3], p[4]
            offset.pitch, offset.roll, offset.yaw = p[5], p[6], p[7]
            sync_sliders(entry)

            if do_attach(veh, p[2], p[3], p[4], p[5], p[6], p[7]) then
                attached_player_name = pname
                safe_notify('Attached to ' .. pname .. ' (' .. p[1] .. ')')
            end
        end)
    end

    -- Attach / Detach
    p_menu:button('Attach'):event(menu.event.click, function()
        local veh = get_player_vehicle(pid)
        if not veh then safe_notify(pname .. ' is not in a vehicle'); return end
        if do_attach(veh, offset.x, offset.y, offset.z, offset.pitch, offset.roll, offset.yaw) then
            attached_player_name = pname
            safe_notify('Attached to ' .. pname)
        end
    end)

    p_menu:button('Detach'):event(menu.event.click, function()
        if attached_vehicle then
            do_detach()
            safe_notify('Detached')
        else
            safe_notify('Not attached')
        end
    end)

    -- Adjust Position sub-submenu inside player tab
    local pos_sub = p_menu:submenu('Adjust Position')
    if pos_sub then
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

    -- Remove departed players
    for pid, entry in pairs(player_entries) do
        if not session_ids[pid] then
            if attached_player_name and entry.name == attached_player_name then
                do_detach()
                safe_notify(entry.name .. ' left — detached', { icon = notify.icon.hazard })
            end
            remove_player(pid)
        end
    end

    -- Add new players
    for _, p in ipairs(player_list) do
        local p_ok, p_id, p_name = pcall(function() return p.id, p.name end)
        if p_ok and p_id and p_id ~= my_id and p_name then
            local name = tostring(p_name)
            if #name > 0 and not player_entries[p_id] and is_valid_player(p_id) then
                pcall(create_player_menu, p_id, name)
            end
        end
    end

    local total = 0
    for _ in pairs(player_entries) do total = total + 1 end
    safe_notify('Players: ' .. total)
end

-- ─── Quick Detach ───────────────────────────────────────────────────
root:button('Detach'):event(menu.event.click, function()
    if attached_vehicle then
        local name = attached_player_name or 'vehicle'
        do_detach()
        safe_notify('Detached from ' .. name)
    else
        safe_notify('Not attached')
    end
end)

-- ─── Refresh Players ────────────────────────────────────────────────
local refresh_requested = false

root:button('Refresh Players'):event(menu.event.click, function()
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
        for pid, entry in pairs(player_entries) do
            if not is_valid_player(pid) then
                if attached_player_name and entry.name == attached_player_name then
                    do_detach()
                    safe_notify(entry.name .. ' left — detached', { icon = notify.icon.hazard })
                end
                remove_player(pid)
            end
        end
    end
end)

-- ─── Ready ──────────────────────────────────────────────────────────
local mode = use_sliders and 'sliders' or 'buttons'
safe_notify('v' .. SCRIPT_VERSION .. ' (' .. mode .. ')', { icon = notify.icon.info })
