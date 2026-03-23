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
-- Player Attach - Lexis Mod Menu Script
-- Attach your local entity (ped or vehicle) to another player's vehicle
-- Inspired by Lexis Player > Vehicle > Attachment and CalmBum for Stand
--

local SCRIPT_NAME = 'Player Attach'
local SCRIPT_VERSION = '3.2.0'

-----------------------------------------------------------------------
-- Permission check
-----------------------------------------------------------------------
local perm_ok, perm_val = pcall(function()
    return this.permissions() & permission.natives
end)
if not perm_ok or not perm_val or perm_val == 0 then
    pcall(notify.push, SCRIPT_NAME, 'Natives permission required. Exiting.', { icon = notify.icon.hazard })
    pcall(this.unload)
    return
end

-----------------------------------------------------------------------
-- Native hashes
-----------------------------------------------------------------------
local N_ATTACH_ENTITY_TO_ENTITY                = 0x6B9BBD38AB0796DF
local N_DETACH_ENTITY                          = 0x961AC54BF0613F5D
local N_IS_ENTITY_ATTACHED                     = 0xB346476EF1A64897
local N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION = 0x1A9205C1B9EE827F
local N_DOES_ENTITY_EXIST                      = 0x7239B21A38F536BA

-----------------------------------------------------------------------
-- Safe native call wrapper
-----------------------------------------------------------------------
local function call_native(hash, ...)
    local ok, result = pcall(invoker.call, hash, ...)
    if not ok then
        return nil
    end
    return result
end

local function native_to_bool(result)
    if result == nil then
        return false
    end
    local t = type(result)
    if t == 'boolean' then
        return result
    end
    if t == 'number' then
        return result ~= 0
    end
    if t == 'table' then
        if result.bool ~= nil then return result.bool end
        if result.int ~= nil then return result.int ~= 0 end
        return false
    end
    local ok1, val1 = pcall(tonumber, result)
    if ok1 and val1 ~= nil then return val1 ~= 0 end
    local ok2, val2 = pcall(function() return result.bool end)
    if ok2 and type(val2) == 'boolean' then return val2 end
    return false
end

-----------------------------------------------------------------------
-- Safe notify wrapper
-----------------------------------------------------------------------
local function safe_notify(text, opts)
    pcall(notify.push, SCRIPT_NAME, tostring(text), opts)
end

-----------------------------------------------------------------------
-- State
-----------------------------------------------------------------------
local attached_vehicle = nil
local attached_player_name = nil
local collision_disabled = false

local attach_params = {
    active = false,
    vehicle = nil,
    x = 0.0,
    y = 0.0,
    z = 0.0,
    pitch = 0.0,
    roll = 0.0,
    yaw = 0.0,
}

-----------------------------------------------------------------------
-- Preset positions { name, x, y, z, pitch, roll, yaw }
-----------------------------------------------------------------------
local presets = {
    { 'Roof',         0.0,   0.0,  1.2,  0.0, 0.0,   0.0 },
    { 'Hood',         0.0,   2.5,  0.8,  0.0, 0.0,   0.0 },
    { 'Trunk',        0.0,  -2.5,  0.8,  0.0, 0.0, 180.0 },
    { 'Left Side',   -1.2,   0.0,  0.5,  0.0, 0.0, -90.0 },
    { 'Right Side',   1.2,   0.0,  0.5,  0.0, 0.0,  90.0 },
    { 'Hanging Back', 0.0,  -2.0,  0.2,  0.0, 0.0, 180.0 },
}

-----------------------------------------------------------------------
-- Entity helpers
-----------------------------------------------------------------------
local function entity_exists(handle)
    if not handle or handle == 0 then
        return false
    end
    return native_to_bool(call_native(N_DOES_ENTITY_EXIST, handle))
end

local function get_my_entity()
    local ok, me = pcall(players.me)
    if not ok or not me then
        return nil
    end
    local ok2, result = pcall(function()
        if me.in_vehicle and me.vehicle and me.vehicle ~= 0 then
            return me.vehicle
        end
        if me.ped and me.ped ~= 0 then
            return me.ped
        end
        return nil
    end)
    if ok2 then
        return result
    end
    return nil
end

local function is_entity_attached(entity)
    if not entity or entity == 0 then
        return false
    end
    return native_to_bool(call_native(N_IS_ENTITY_ATTACHED, entity))
end

-----------------------------------------------------------------------
-- Check if a player slot is real (has a valid ped in the game world)
-----------------------------------------------------------------------
local function is_valid_player(pid)
    local ok, target = pcall(players.get, pid)
    if not ok or not target then
        return false
    end
    local ok2, ped = pcall(function() return target.ped end)
    if not ok2 or not ped or ped == 0 then
        return false
    end
    return entity_exists(ped)
end

-----------------------------------------------------------------------
-- Core attach / detach (no yields — safe for menu callbacks)
-----------------------------------------------------------------------
local function raw_attach(entity, target_vehicle, x, y, z, pitch, roll, yaw)
    call_native(N_ATTACH_ENTITY_TO_ENTITY,
        entity,
        target_vehicle,
        0,
        x + 0.0, y + 0.0, z + 0.0,
        pitch + 0.0, roll + 0.0, yaw + 0.0,
        1, 0, 1, 0, 0, 1
    )
end

local function do_attach(target_vehicle, x, y, z, pitch, roll, yaw)
    local entity = get_my_entity()
    if not entity then
        safe_notify('Could not get your entity')
        return false
    end

    if not entity_exists(target_vehicle) then
        safe_notify('Target vehicle no longer exists')
        return false
    end

    if is_entity_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    raw_attach(entity, target_vehicle, x, y, z, pitch, roll, yaw)

    attached_vehicle = target_vehicle
    attach_params.active = true
    attach_params.vehicle = target_vehicle
    attach_params.x = x
    attach_params.y = y
    attach_params.z = z
    attach_params.pitch = pitch
    attach_params.roll = roll
    attach_params.yaw = yaw

    if collision_disabled then
        call_native(N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, 0, 0)
    end

    return true
end

local function do_detach()
    attach_params.active = false
    attach_params.vehicle = nil

    local entity = get_my_entity()
    if entity and is_entity_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    attached_vehicle = nil
    attached_player_name = nil
end

-----------------------------------------------------------------------
-- Helper: get a player's vehicle handle (returns nil if not in vehicle)
-----------------------------------------------------------------------
local function get_player_vehicle(pid)
    local ok, target = pcall(players.get, pid)
    if not ok or not target then return nil end
    local ok2, veh = pcall(function()
        if target.in_vehicle and target.vehicle and target.vehicle ~= 0 then
            return target.vehicle
        end
        return nil
    end)
    if ok2 then return veh end
    return nil
end

-----------------------------------------------------------------------
-- Persistent re-attach thread (coroutine — yield is safe)
-----------------------------------------------------------------------
util.create_thread(function()
    while true do
        util.yield(200)

        if not attach_params.active or not attach_params.vehicle then
            goto continue
        end

        local entity = get_my_entity()
        if not entity then
            goto continue
        end

        if not entity_exists(attach_params.vehicle) then
            attach_params.active = false
            attach_params.vehicle = nil
            attached_vehicle = nil
            attached_player_name = nil
            safe_notify('Vehicle no longer exists, detached', { icon = notify.icon.hazard })
            goto continue
        end

        if not is_entity_attached(entity) then
            raw_attach(
                entity,
                attach_params.vehicle,
                attach_params.x, attach_params.y, attach_params.z,
                attach_params.pitch, attach_params.roll, attach_params.yaw
            )
            if collision_disabled then
                call_native(N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, 0, 0)
            end
        end

        ::continue::
    end
end)

-----------------------------------------------------------------------
-- Menu setup
-----------------------------------------------------------------------
local root = menu.root()
if not root then
    safe_notify('Failed to get menu root. Exiting.', { icon = notify.icon.hazard })
    pcall(this.unload)
    return
end

-----------------------------------------------------------------------
-- Player tracking — keyed by pid, prevents duplicates
-- player_entries[pid] = { menu = submenu_handle, name = string }
-----------------------------------------------------------------------
local player_entries = {}

-----------------------------------------------------------------------
-- Safe menu deletion helper
-----------------------------------------------------------------------
local function safe_delete_menu(m)
    if not m then return end
    local ok = pcall(function() m:delete() end)
    if not ok then
        pcall(function() m:remove() end)
    end
end

-----------------------------------------------------------------------
-- Global offset (shared — only one attachment at a time)
-----------------------------------------------------------------------
local offset = { x = 0.0, y = 0.0, z = 0.0, pitch = 0.0, roll = 0.0, yaw = 0.0 }

local function global_reattach()
    if not attached_vehicle then return end
    pcall(do_attach, attached_vehicle,
        offset.x, offset.y, offset.z,
        offset.pitch, offset.roll, offset.yaw)
end

-----------------------------------------------------------------------
-- Quick detach at top of root menu
-----------------------------------------------------------------------
local detach_btn = root:button('Detach')
detach_btn:tooltip('Quick detach from any vehicle you are attached to')
detach_btn:event(menu.event.click, function()
    if attached_vehicle then
        local name = attached_player_name or 'vehicle'
        do_detach()
        safe_notify('Detached from ' .. name)
    else
        safe_notify('Not attached to anything')
    end
end)

-----------------------------------------------------------------------
-- Adjust Position — on root menu so it always shows
-----------------------------------------------------------------------
local pos_menu = root:submenu('Adjust Position')

local step_sizes = { 0.05, 0.1, 0.25, 0.5, 1.0 }
local step_names = { '0.05', '0.1', '0.25', '0.5', '1.0' }
local rot_steps  = { 1.0, 5.0, 15.0, 30.0, 45.0 }
local rot_names  = { '1', '5', '15', '30', '45' }
local step_idx = 2

local step_btn = pos_menu:button('Cycle Step Size')
step_btn:tooltip('Click to cycle: 0.05 / 0.1 / 0.25 / 0.5 / 1.0')
step_btn:event(menu.event.click, function()
    step_idx = step_idx % 5 + 1
    safe_notify('Step: ' .. step_names[step_idx] .. ' Rot: ' .. rot_names[step_idx])
end)

local function make_axis(key, label_minus, label_plus, is_rot)
    local bm = pos_menu:button(label_minus)
    bm:event(menu.event.click, function()
        local s = is_rot and rot_steps[step_idx] or step_sizes[step_idx]
        offset[key] = offset[key] - s
        global_reattach()
        safe_notify(key .. ' = ' .. string.format('%.2f', offset[key]))
    end)
    local bp = pos_menu:button(label_plus)
    bp:event(menu.event.click, function()
        local s = is_rot and rot_steps[step_idx] or step_sizes[step_idx]
        offset[key] = offset[key] + s
        global_reattach()
        safe_notify(key .. ' = ' .. string.format('%.2f', offset[key]))
    end)
end

make_axis('x',     'Left',       'Right',      false)
make_axis('y',     'Back',       'Front',      false)
make_axis('z',     'Down',       'Up',         false)
make_axis('pitch', 'Pitch Down', 'Pitch Up',   true)
make_axis('roll',  'Roll Left',  'Roll Right', true)
make_axis('yaw',   'Yaw Left',   'Yaw Right',  true)

local reset_btn = pos_menu:button('Reset Position')
reset_btn:tooltip('Reset all offsets to 0')
reset_btn:event(menu.event.click, function()
    offset.x = 0.0; offset.y = 0.0; offset.z = 0.0
    offset.pitch = 0.0; offset.roll = 0.0; offset.yaw = 0.0
    global_reattach()
    safe_notify('Position reset to 0')
end)

-----------------------------------------------------------------------
-- Disable Collision — on root menu
-----------------------------------------------------------------------
local col_toggle = root:toggle('Disable Collision')
col_toggle:tooltip('Clip through the vehicle instead of colliding with it')
col_toggle:event(menu.event.change, function(val)
    collision_disabled = val
    if attached_vehicle and collision_disabled then
        local entity = get_my_entity()
        if entity then
            call_native(N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, 0, 0)
        end
        safe_notify('Collision disabled')
    end
end)

-----------------------------------------------------------------------
-- Create submenu for one player (presets + attach/detach only)
-----------------------------------------------------------------------
local function create_player_menu(pid, pname)
    local p_menu = root:submenu(pname)
    if not p_menu then return false end

    -- Track IMMEDIATELY — prevents duplicate submenus
    player_entries[pid] = { menu = p_menu, name = pname }

    -- Presets
    for _, preset in ipairs(presets) do
        local btn = p_menu:button(preset[1])
        btn:tooltip('Attach at ' .. preset[1])
        btn:event(menu.event.click, function()
            local veh = get_player_vehicle(pid)
            if not veh then
                safe_notify(pname .. ' is not in a vehicle')
                return
            end

            offset.x = preset[2]
            offset.y = preset[3]
            offset.z = preset[4]
            offset.pitch = preset[5]
            offset.roll = preset[6]
            offset.yaw = preset[7]

            if do_attach(veh, preset[2], preset[3], preset[4], preset[5], preset[6], preset[7]) then
                attached_player_name = pname
                safe_notify('Attached to ' .. pname .. ' (' .. preset[1] .. ')')
            end
        end)
    end

    -- Attach with current offset
    local attach_btn = p_menu:button('Attach')
    attach_btn:tooltip('Attach with current Adjust Position values')
    attach_btn:event(menu.event.click, function()
        local veh = get_player_vehicle(pid)
        if not veh then
            safe_notify(pname .. ' is not in a vehicle')
            return
        end

        if do_attach(veh, offset.x, offset.y, offset.z, offset.pitch, offset.roll, offset.yaw) then
            attached_player_name = pname
            safe_notify('Attached to ' .. pname)
        end
    end)

    -- Detach
    local detach_btn2 = p_menu:button('Detach')
    detach_btn2:tooltip('Detach from this player')
    detach_btn2:event(menu.event.click, function()
        if attached_vehicle then
            do_detach()
            safe_notify('Detached')
        else
            safe_notify('Not attached to anything')
        end
    end)

    return true
end

-----------------------------------------------------------------------
-- Remove a single player's menu entry
-----------------------------------------------------------------------
local function remove_player(pid)
    local entry = player_entries[pid]
    if not entry then return end
    safe_delete_menu(entry.menu)
    player_entries[pid] = nil
end

-----------------------------------------------------------------------
-- Refresh: scan player list, add new, remove departed.
-----------------------------------------------------------------------
local function refresh_players()
    local ok, player_list = pcall(players.list)
    if not ok or not player_list then
        safe_notify('Could not get player list')
        return
    end

    local ok_me, my = pcall(players.me)
    local my_id = -1
    if ok_me and my then
        local ok_id, id_val = pcall(function() return my.id end)
        if ok_id and id_val then my_id = id_val end
    end

    local current = {}
    for _, player in ipairs(player_list) do
        local p_ok, p_id, p_name = pcall(function()
            return player.id, player.name
        end)
        if p_ok and p_id and p_id ~= my_id and p_name then
            local name_str = tostring(p_name)
            if #name_str > 0 and is_valid_player(p_id) then
                current[p_id] = name_str
            end
        end
    end

    for pid, entry in pairs(player_entries) do
        if not current[pid] then
            if attached_player_name and entry.name == attached_player_name then
                do_detach()
                safe_notify('Auto-detached: ' .. entry.name .. ' left', { icon = notify.icon.hazard })
            end
            remove_player(pid)
        end
    end

    local added = 0
    for pid, pname in pairs(current) do
        if not player_entries[pid] then
            pcall(create_player_menu, pid, pname)
            if player_entries[pid] then
                added = added + 1
            end
        end
    end

    local total = 0
    for _ in pairs(player_entries) do total = total + 1 end
    safe_notify('Found ' .. total .. ' players')
end

-----------------------------------------------------------------------
-- Cleanup thread
-----------------------------------------------------------------------
util.create_thread(function()
    while true do
        util.yield(5000)
        for pid, entry in pairs(player_entries) do
            if not is_valid_player(pid) then
                if attached_player_name and entry.name == attached_player_name then
                    do_detach()
                    safe_notify('Auto-detached: ' .. entry.name .. ' left', { icon = notify.icon.hazard })
                end
                remove_player(pid)
            end
        end
    end
end)

-----------------------------------------------------------------------
-- Refresh button
-----------------------------------------------------------------------
local refresh_requested = false

local refresh_btn = root:button('Refresh Players')
refresh_btn:tooltip('Refresh the player list')
refresh_btn:event(menu.event.click, function()
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

safe_notify('v' .. SCRIPT_VERSION .. ' loaded — click Refresh Players to populate', { icon = notify.icon.info })
