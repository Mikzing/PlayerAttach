-- ╔══════════════════════════════════════════════════════════════╗
-- ║                                                              ║
-- ║   ██████╗ ██╗      █████╗ ██╗   ██╗███████╗██████╗           ║
-- ║   ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗         ║
-- ║   ██████╔╝██║     ███████║ ╚████╔╝ █████╗  ██████╔╝         ║
-- ║   ██╔═══╝ ██║     ██╔══██║  ╚██╔╝  ██╔══╝  ██╔══██╗         ║
-- ║   ██║     ███████╗██║  ██║   ██║   ███████╗██║  ██║         ║
-- ║   ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝         ║
-- ║    █████╗ ████████╗████████╗ █████╗  ██████╗██╗  ██╗         ║
-- ║   ██╔══██╗╚══██╔══╝╚══██╔══╝██╔══██╗██╔════╝██║  ██║         ║
-- ║   ███████║   ██║      ██║   ███████║██║     ███████║         ║
-- ║   ██╔══██║   ██║      ██║   ██╔══██║██║     ██╔══██║         ║
-- ║   ██║  ██║   ██║      ██║   ██║  ██║╚██████╗██║  ██║         ║
-- ║   ╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝         ║
-- ║                                                              ║
-- ║              ─── crafted by Mikz ───                         ║
-- ║                                                              ║
-- ╚══════════════════════════════════════════════════════════════╝
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

local function get_my_ped()
    local ped = players.me().ped
    if ped ~= 0 then return ped end
    return nil
end

local function get_player_vehicle(player)
    if player.in_vehicle and player.vehicle ~= 0 then return player.vehicle end
    return nil
end

local function find_player_by_name(name)
    for _, p in ipairs(players.list()) do
        if p.name == name then return p end
    end
    return nil
end

local function get_target_vehicle()
    if players.is_target_session() then return nil end
    local target = players.target()
    if not target then return nil end
    return get_player_vehicle(target)
end

local function get_target_name()
    if players.is_target_session() then return 'session' end
    local target = players.target()
    if not target then return 'unknown' end
    return target.name
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

-- ─── Slider definitions (shared by both menus) ─────────────────────
-- { label, key, min, max, normal_step, fine_step, fmt, tooltip }
local slider_defs = {
    { 'X  Left / Right', 'x',   -10.0,  10.0, 0.10, 0.05, '%.2f', 'Move left (-) or right (+)' },
    { 'Y  Back / Front', 'y',   -10.0,  10.0, 0.10, 0.05, '%.2f', 'Move backward (-) or forward (+)' },
    { 'Z  Down / Up',    'z',   -10.0,  10.0, 0.10, 0.05, '%.2f', 'Move down (-) or up (+)' },
    { 'Yaw',             'yaw', -180.0, 180.0, 5.0,  1.0,  '%.0f', 'Rotate left/right (turn)' },
}

local fine_mode = false

-- ─── Default position (Roof) — safe spawn point above the vehicle ──
local DEFAULT_OFFSET = { x = 0.0, y = 0.0, z = 1.2, yaw = 0.0 }

-- ─── Attachment state ───────────────────────────────────────────────
local attached_player_name = nil
local offset = { x = DEFAULT_OFFSET.x, y = DEFAULT_OFFSET.y, z = DEFAULT_OFFSET.z, yaw = DEFAULT_OFFSET.yaw }

-- Registry of every slider group so presets/resets can sync all widgets
local all_slider_groups = {}
local all_fine_buttons  = {}

local function sync_all_sliders()
    for _, group in ipairs(all_slider_groups) do
        for _, s in ipairs(group) do
            s.widget.value = offset[s.key]
        end
    end
end

local function sync_fine_mode()
    for _, btn in ipairs(all_fine_buttons) do
        btn.name = fine_mode and 'Fine Mode: ON' or 'Fine Mode: OFF'
    end
    for _, group in ipairs(all_slider_groups) do
        for _, s in ipairs(group) do
            local step = fine_mode and s.fine or s.norm
            s.widget:fmt(s.fmt, s.lo, s.hi, step)
        end
    end
end

local function set_offset(x, y, z, yaw)
    offset.x, offset.y, offset.z, offset.yaw = x, y, z, yaw
    sync_all_sliders()
end

local function reset_offset()
    set_offset(DEFAULT_OFFSET.x, DEFAULT_OFFSET.y, DEFAULT_OFFSET.z, DEFAULT_OFFSET.yaw)
end

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
    local entity = get_my_ped()
    if not entity then notify.push(SCRIPT_NAME, 'Could not get your entity'); return false end

    if call_native(N_IS_ENTITY_ATTACHED, entity).bool and attach_state.vehicle ~= veh then
        pcall(call_native, N_DETACH_ENTITY, entity, 1, 1)
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

    local entity = get_my_ped()
    if entity then
        pcall(call_native, N_DETACH_ENTITY, entity, 1, 1)
    end

    set_idle_anims(true)
    attached_player_name = nil
end

local function reattach()
    if not attach_state.active or not attach_state.vehicle then return end
    local entity = get_my_ped()
    if not entity then return end

    attach_state.x = offset.x
    attach_state.y = offset.y
    attach_state.z = offset.z
    attach_state.yaw = offset.yaw

    raw_attach(entity, attach_state.vehicle, offset.x, offset.y, offset.z, offset.yaw)
end

-- ─── Helper: build adjust-position controls into a submenu ─────────
local function build_adjust_controls(parent)
    local sliders = {}

    for _, d in ipairs(slider_defs) do
        local label, key, lo, hi, norm, fine, fmt, tip = d[1], d[2], d[3], d[4], d[5], d[6], d[7], d[8]
        local init_step = fine_mode and fine or norm
        local slider = parent:number_float(label, menu.type.scroll)
            :fmt(fmt, lo, hi, init_step)
            :tooltip(tip)
            :event(menu.event.click, function(opt)
                offset[key] = opt.value
                reattach()
            end)
        slider.value = offset[key]
        sliders[#sliders + 1] = { widget = slider, key = key, norm = norm, fine = fine, fmt = fmt, lo = lo, hi = hi }
    end

    local fine_btn = parent:button(fine_mode and 'Fine Mode: ON' or 'Fine Mode: OFF')
        :tooltip('Toggle between normal (0.10) and fine (0.05) step size')
        :event(menu.event.click, function()
            fine_mode = not fine_mode
            sync_fine_mode()
        end)
    all_fine_buttons[#all_fine_buttons + 1] = fine_btn

    parent:button('Reset Position')
        :tooltip('Reset offsets back to roof (default)')
        :event(menu.event.click, function()
            reset_offset()
            reattach()
            notify.push(SCRIPT_NAME, 'Position reset')
        end)

    all_slider_groups[#all_slider_groups + 1] = sliders
    return sliders
end

-- ─── Re-attach thread ──────────────────────────────────────────────
util.create_thread(function()
    while true do
        util.yield(200)
        if not attach_state.active or not attach_state.vehicle then goto next end

        local entity = get_my_ped()
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

-- ─── Helper: check if player slot is valid ──────────────────────────
local function is_valid_player(p)
    return p and p.name and p.name ~= '' and p.ped ~= 0
end

-- ─── Helper: build per-player controls ────────────────────────────
local function build_player_entry(parent, player)
    local name = player.name
    local psub = parent:submenu(name)
    psub:tooltip('Attach options for ' .. name)

    -- Attach with current offsets (reset to Roof if new target)
    psub:button('Attach')
        :tooltip('Attach to ' .. name .. '\'s vehicle using current offsets')
        :event(menu.event.click, function()
            local p = find_player_by_name(name)
            if not p then notify.push(SCRIPT_NAME, name .. ' not found'); return end
            local veh = get_player_vehicle(p)
            if not veh then notify.push(SCRIPT_NAME, name .. ' is not in a vehicle'); return end
            if attached_player_name ~= name then reset_offset() end
            if do_attach(veh, offset.x, offset.y, offset.z, offset.yaw) then
                attached_player_name = name
                notify.push(SCRIPT_NAME, 'Attached to ' .. name)
            end
        end)

    -- Detach
    psub:button('Detach')
        :tooltip('Detach from ' .. name)
        :event(menu.event.click, function()
            do_detach()
            notify.push(SCRIPT_NAME, 'Detached from ' .. name)
        end)

    -- Presets
    local pp = psub:submenu('Presets')
    pp:tooltip('Quick-attach to common positions on ' .. name .. '\'s vehicle')

    for _, preset in ipairs(presets) do
        pp:button(preset[1])
            :tooltip(preset[2])
            :event(menu.event.click, function()
                local p = find_player_by_name(name)
                if not p then notify.push(SCRIPT_NAME, name .. ' not found'); return end
                local veh = get_player_vehicle(p)
                if not veh then notify.push(SCRIPT_NAME, name .. ' is not in a vehicle'); return end

                set_offset(preset[3], preset[4], preset[5], preset[6])

                if do_attach(veh, offset.x, offset.y, offset.z, offset.yaw) then
                    attached_player_name = name
                    notify.push(SCRIPT_NAME, 'Attached to ' .. name .. ' (' .. preset[1] .. ')')
                end
            end)
    end

    -- Adjust Position
    local ap = psub:submenu('Adjust Position')
    ap:tooltip('Fine-tune your position on ' .. name .. '\'s vehicle')
    build_adjust_controls(ap)

    return psub
end

-- ─── Self menu (menu.root) ─────────────────────────────────────────
local root = menu.root()

-- Player list submenu (dynamically managed via join/leave events)
local player_list_sub = root:submenu('Players')
player_list_sub:tooltip('Browse online players and attach to their vehicle')

local player_menu_entries = {}

do
    local me = players.me()
    for _, p in ipairs(players.list()) do
        if is_valid_player(p) and p.name ~= me.name then
            player_menu_entries[p.name] = build_player_entry(player_list_sub, p)
        end
    end
end

events.subscribe(events.event.player_join, function(data)
    if not is_valid_player(data.player) then return end
    local name = data.player.name
    if name == players.me().name then return end
    if not player_menu_entries[name] then
        player_menu_entries[name] = build_player_entry(player_list_sub, data.player)
    end
end)

events.subscribe(events.event.player_leave, function(data)
    local name = data.player.name
    local entry = player_menu_entries[name]
    if entry then
        entry:delete()
        player_menu_entries[name] = nil
    end
end)

-- Detach button
root:button('Detach')
    :tooltip('Quick detach from any vehicle you are attached to')
    :event(menu.event.click, function()
        local name = attached_player_name or 'vehicle'
        do_detach()
        notify.push(SCRIPT_NAME, 'Detached from ' .. name)
    end)

-- Adjust Position submenu (global — applies to current attachment)
local root_pos_sub = root:submenu('Adjust Position')
root_pos_sub:tooltip('Fine-tune your X/Y/Z position and rotation on the vehicle')
build_adjust_controls(root_pos_sub)

-- ─── Player menu (menu.player_root) ────────────────────────────────
local player_root = menu.player_root()

-- Attach button
player_root:button('Attach')
    :tooltip('Attach to this player\'s vehicle using current offsets')
    :event(menu.event.click, function()
        local name = get_target_name()
        if name == players.me().name then notify.push(SCRIPT_NAME, 'Cannot attach to yourself'); return end
        local veh = get_target_vehicle()
        if not veh then notify.push(SCRIPT_NAME, name .. ' is not in a vehicle'); return end
        if attached_player_name ~= name then reset_offset() end
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
            local name = get_target_name()
            if name == players.me().name then notify.push(SCRIPT_NAME, 'Cannot attach to yourself'); return end
            local veh = get_target_vehicle()
            if not veh then notify.push(SCRIPT_NAME, name .. ' is not in a vehicle'); return end

            set_offset(p[3], p[4], p[5], p[6])

            if do_attach(veh, offset.x, offset.y, offset.z, offset.yaw) then
                attached_player_name = name
                notify.push(SCRIPT_NAME, 'Attached to ' .. name .. ' (' .. p[1] .. ')')
            end
        end)
end

-- Adjust Position submenu
local pos_sub = player_root:submenu('Adjust Position')
pos_sub:tooltip('Fine-tune your X/Y/Z position and rotation on the vehicle')
build_adjust_controls(pos_sub)

-- ─── Ready ──────────────────────────────────────────────────────────
notify.push(SCRIPT_NAME, 'v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
