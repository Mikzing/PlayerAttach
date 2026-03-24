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
-- Player Attach v5.0.0 — Lexis Script
-- Attach yourself to any player's vehicle
--

local SCRIPT_NAME    = 'Player Attach'
local SCRIPT_VERSION = '5.0.0'

-- ─── Permission check ───────────────────────────────────────────────
if this.permissions() & permission.natives == 0 then
    notify.push(SCRIPT_NAME, 'Natives permission required.', { icon = notify.icon.hazard })
    this.unload()
    return
end

-- ─── Natives ────────────────────────────────────────────────────────
local N_ATTACH_ENTITY_TO_ENTITY             = 0x6B9BBD38AB0796DF
local N_DETACH_ENTITY                       = 0x961AC54BF0613F5D
local N_IS_ENTITY_ATTACHED                  = 0xB346476EF1A64897
local N_SET_PED_CAN_PLAY_AMBIENT_ANIMS      = 0x6EC47A344923E1ED
local N_SET_PED_CAN_PLAY_AMBIENT_BASE_ANIMS = 0x0EB0585D15254740

-- ─── Utilities ──────────────────────────────────────────────────────
local function call_native(hash, ...)
    return invoker.call(hash, ...)
end

local function get_my_entity()
    local me = players.me()
    if me.in_vehicle and me.vehicle ~= 0 then return me.vehicle end
    if me.ped ~= 0 then return me.ped end
    return nil
end

local function get_target_vehicle()
    if players.is_target_session() then return nil end
    local t = players.target()
    if t.in_vehicle and t.vehicle ~= 0 then return t.vehicle end
    return nil
end

local function get_target_name()
    if players.is_target_session() then return 'session' end
    return players.target().name
end

local function set_idle_anims(enabled)
    local ped = players.me().ped
    if ped == 0 then return end
    local v = enabled and 1 or 0
    call_native(N_SET_PED_CAN_PLAY_AMBIENT_ANIMS, ped, v)
    call_native(N_SET_PED_CAN_PLAY_AMBIENT_BASE_ANIMS, ped, v)
end

-- ─── Presets { name, tooltip, x, y, z, yaw } ───────────────────────
local presets = {
    { 'Roof',         'Stand on top of the vehicle',             0.0,   0.0,  1.2,   0.0 },
    { 'Hood',         'Stand on the front hood',                 0.0,   2.5,  0.8,   0.0 },
    { 'Trunk',        'Stand on the back trunk, facing rear',    0.0,  -2.5,  0.8, 180.0 },
    { 'Left Side',    'Hang off the left side, facing outward', -1.2,   0.0,  0.5, -90.0 },
    { 'Right Side',   'Hang off the right side, facing outward', 1.2,   0.0,  0.5,  90.0 },
    { 'Hanging Back', 'Cling to the rear bumper',                0.0,  -2.0,  0.2, 180.0 },
}

-- ─── Attachment state ───────────────────────────────────────────────
local attached_player_name = nil
local offset = { x = 0.0, y = 0.0, z = 0.0, yaw = 0.0 }

local attach_state = {
    active  = false,
    vehicle = nil,
    x = 0.0, y = 0.0, z = 0.0,
    yaw = 0.0,
}

local function raw_attach(entity, veh, x, y, z, yaw)
    call_native(N_ATTACH_ENTITY_TO_ENTITY,
        entity, veh, 0,
        x + 0.0, y + 0.0, z + 0.0,
        0.0, 0.0, yaw + 0.0,
        0, 1, 1, 0, 2, 1)
end

local function do_attach(veh, x, y, z, yaw)
    local entity = get_my_entity()
    if not entity then notify.push(SCRIPT_NAME, 'Could not get your entity'); return false end

    if call_native(N_IS_ENTITY_ATTACHED, entity).bool then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    raw_attach(entity, veh, x, y, z, yaw)
    set_idle_anims(false)

    attach_state.active  = true
    attach_state.vehicle = veh
    attach_state.x, attach_state.y, attach_state.z = x, y, z
    attach_state.yaw = yaw
    return true
end

local function do_detach()
    attach_state.active  = false
    attach_state.vehicle = nil

    local entity = get_my_entity()
    if entity then
        pcall(call_native, N_DETACH_ENTITY, entity, 1, 1)
    end

    set_idle_anims(true)
    attached_player_name = nil
end

local function reattach()
    if not attach_state.vehicle then return end
    do_attach(attach_state.vehicle,
        offset.x, offset.y, offset.z, offset.yaw)
end

-- ─── Re-attach thread ──────────────────────────────────────────────
util.create_thread(function()
    while true do
        util.yield(200)
        if not attach_state.active or not attach_state.vehicle then goto next end

        local entity = get_my_entity()
        if not entity then goto next end

        if not call_native(N_IS_ENTITY_ATTACHED, entity).bool then
            raw_attach(entity, attach_state.vehicle,
                attach_state.x, attach_state.y, attach_state.z,
                attach_state.yaw)
            set_idle_anims(false)
        end

        ::next::
    end
end)

-- ─── Auto-detach on player leave ────────────────────────────────────
events.subscribe(events.event.player_leave, function(data)
    if attached_player_name and data.player.name == attached_player_name then
        do_detach()
        notify.push(SCRIPT_NAME, data.player.name .. ' left — detached', { icon = notify.icon.player_leave })
    end
end)

-- ─── Self menu (menu.root) ─────────────────────────────────────────
local root = menu.root()

root:button('Detach')
    :tooltip('Quick detach from any vehicle you are attached to')
    :event(menu.event.click, function()
        local name = attached_player_name or 'vehicle'
        do_detach()
        notify.push(SCRIPT_NAME, 'Detached from ' .. name)
    end)

-- ─── Player menu (menu.player_root) ────────────────────────────────
local player_root = menu.player_root()

-- Attach button
player_root:button('Attach')
    :tooltip('Attach to this player\'s vehicle using current offsets')
    :event(menu.event.click, function()
        local veh = get_target_vehicle()
        local name = get_target_name()
        if not veh then notify.push(SCRIPT_NAME, name .. ' is not in a vehicle'); return end
        if do_attach(veh, offset.x, offset.y, offset.z, offset.yaw) then
            attached_player_name = name
            notify.push(SCRIPT_NAME, 'Attached to ' .. name)
        end
    end)

-- Detach button
player_root:button('Detach')
    :tooltip('Detach from this player')
    :event(menu.event.click, function()
        local name = attached_player_name or get_target_name()
        do_detach()
        notify.push(SCRIPT_NAME, 'Detached from ' .. name)
    end)

-- Presets submenu
local presets_sub = player_root:submenu('Presets')
presets_sub:tooltip('Quick-attach to common positions on the vehicle')

for _, p in ipairs(presets) do
    presets_sub:button(p[1])
        :tooltip(p[2])
        :event(menu.event.click, function()
            local veh = get_target_vehicle()
            local name = get_target_name()
            if not veh then notify.push(SCRIPT_NAME, name .. ' is not in a vehicle'); return end

            offset.x, offset.y, offset.z = p[3], p[4], p[5]
            offset.yaw = p[6]

            if do_attach(veh, p[3], p[4], p[5], p[6]) then
                attached_player_name = name
                notify.push(SCRIPT_NAME, 'Attached to ' .. name .. ' (' .. p[1] .. ')')
            end
        end)
end

-- Adjust Position submenu
local pos_sub = player_root:submenu('Adjust Position')
pos_sub:tooltip('Fine-tune your X/Y/Z position and rotation on the vehicle')

local slider_defs = {
    { 'X  Left / Right', 'x',   -10.0,  10.0, 0.05, '%.2f', 'Move left (-) or right (+)' },
    { 'Y  Back / Front', 'y',   -10.0,  10.0, 0.05, '%.2f', 'Move backward (-) or forward (+)' },
    { 'Z  Down / Up',    'z',   -10.0,  10.0, 0.05, '%.2f', 'Move down (-) or up (+)' },
    { 'Yaw',             'yaw', -180.0, 180.0, 1.0, '%.0f', 'Rotate left/right (turn)' },
}

for _, d in ipairs(slider_defs) do
    local label, key, lo, hi, step, fmt, tip = d[1], d[2], d[3], d[4], d[5], d[6], d[7]
    pos_sub:number_float(label, menu.type.scroll)
        :fmt(fmt, lo, hi, step)
        :tooltip(tip)
        :event(menu.event.click, function(opt)
            offset[key] = opt.value
            reattach()
        end)
end

pos_sub:button('Reset Position')
    :tooltip('Reset all offsets back to 0')
    :event(menu.event.click, function()
        offset.x, offset.y, offset.z = 0.0, 0.0, 0.0
        offset.yaw = 0.0
        reattach()
        notify.push(SCRIPT_NAME, 'Position reset')
    end)

-- ─── Ready ──────────────────────────────────────────────────────────
notify.push(SCRIPT_NAME, 'v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
