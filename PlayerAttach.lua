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
local SCRIPT_VERSION = '1.4.0'

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
-- Handles all possible return types from invoker.call without
-- assuming the return is a table with .bool / .int / etc.
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
    -- Handle userdata / cdata: try accessors safely via pcall
    local ok1, val1 = pcall(tonumber, result)
    if ok1 and val1 ~= nil then return val1 ~= 0 end
    local ok2, val2 = pcall(function() return result.bool end)
    if ok2 and type(val2) == 'boolean' then return val2 end
    return false
end

-----------------------------------------------------------------------
-- Safe notify wrapper — never crashes on bad args
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

-- Current attachment parameters (stored for re-attach loop)
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
    -- Property access on player objects can be metamethod-backed native queries
    -- that throw if the session state changes. Wrap in pcall.
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
-- Core attach (raw, no notifications, no yields)
-- IMPORTANT: This must NEVER call util.yield() because it is invoked
-- from menu callbacks which are NOT coroutines.
-----------------------------------------------------------------------
local function raw_attach(entity, target_vehicle, x, y, z, pitch, roll, yaw)
    call_native(N_ATTACH_ENTITY_TO_ENTITY,
        entity,
        target_vehicle,
        0,                              -- boneIndex (int)
        x + 0.0, y + 0.0, z + 0.0,    -- position offset (force float)
        pitch + 0.0, roll + 0.0, yaw + 0.0, -- rotation offset (force float)
        1,                              -- p9 (BOOL)
        0,                              -- useSoftPinning (BOOL)
        1,                              -- collision (BOOL)
        0,                              -- isPed (BOOL)
        0,                              -- rotationOrder (int)
        1                               -- syncRot (BOOL)
    )
end

-----------------------------------------------------------------------
-- Core functions
-- IMPORTANT: No util.yield() allowed — these run from menu callbacks.
-----------------------------------------------------------------------
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

    -- Detach first if already attached (for live repositioning)
    -- NO yield here — the engine handles detach+reattach in the same frame fine
    if is_entity_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
    end

    -- Attach
    raw_attach(entity, target_vehicle, x, y, z, pitch, roll, yaw)

    -- Store state
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
    -- Stop the re-attach loop first
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
-- Persistent re-attach thread
-- Keeps you attached when animations, ragdoll, etc try to detach.
-- Runs at a throttled interval (200ms) to avoid stressing the engine.
-- This IS a coroutine context, so util.yield() is safe here.
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
                attach_params.x,
                attach_params.y,
                attach_params.z,
                attach_params.pitch,
                attach_params.roll,
                attach_params.yaw
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

local player_menus = {}

-----------------------------------------------------------------------
-- Safe menu helpers
-----------------------------------------------------------------------
local function safe_delete_menu(m)
    if not m then return end
    local ok = pcall(function() m:delete() end)
    if not ok then
        pcall(function() m:remove() end)
    end
end

-----------------------------------------------------------------------
-- Rebuild signaling — all rebuilds happen inside a dedicated thread
-- so util.yield() is always safe. Callbacks just set a flag.
-----------------------------------------------------------------------
local rebuild_requested = false

local function request_rebuild()
    rebuild_requested = true
end

-----------------------------------------------------------------------
-- Quick detach + refresh at top
-----------------------------------------------------------------------
local detach_btn = root:button('Detach')
detach_btn:tooltip('Quick detach from any vehicle you are attached to')
detach_btn:event(menu.event.click, function()
    -- No util.yield(), no unprotected calls — safe in callback context
    if attached_vehicle then
        local name = attached_player_name or 'vehicle'
        do_detach()
        safe_notify('Detached from ' .. name)
    else
        safe_notify('Not attached to anything')
    end
end)

local refresh_btn = root:button('Refresh Players')
refresh_btn:tooltip('Refresh the player list below')
refresh_btn:event(menu.event.click, function()
    -- Do NOT call rebuild_player_list() directly — it uses util.yield()
    -- which crashes outside a coroutine. Signal the rebuild thread instead.
    request_rebuild()
end)

-----------------------------------------------------------------------
-- Build a full submenu for one player
-- Called ONLY from rebuild thread (coroutine context).
-----------------------------------------------------------------------
local function add_player_menu(player)
    -- Wrap ALL player/self property access in pcall — these are metamethod-backed
    -- native queries that can throw if session state changes.
    local ok_p, label, pid, pname, in_veh = pcall(function()
        local me = players.me()
        if me and player.id == me.id then
            return nil  -- skip self
        end
        return tostring(player.name or 'Unknown'), player.id, tostring(player.name or 'Unknown'), player.in_vehicle
    end)
    if not ok_p or not label then return nil end

    if not in_veh then
        label = label .. ' [On Foot]'
    end

    local p_menu = root:submenu(label)
    if not p_menu then return nil end
    table.insert(player_menus, p_menu)

    --------------------------------------------------------------------
    -- Position
    --------------------------------------------------------------------
    p_menu:breaker('Position')

    local sx = p_menu:number_float('Left / Right', menu.type.scroll)
    sx:fmt('%.2f', -15.0, 15.0, 0.05)
    sx:tooltip('Left or right')

    local sy = p_menu:number_float('Front / Back', menu.type.scroll)
    sy:fmt('%.2f', -15.0, 15.0, 0.05)
    sy:tooltip('Front or back')

    local sz = p_menu:number_float('Up / Down', menu.type.scroll)
    sz:fmt('%.2f', -15.0, 15.0, 0.05)
    sz:tooltip('Up or down')

    --------------------------------------------------------------------
    -- Rotation
    --------------------------------------------------------------------
    p_menu:breaker('Rotation')

    local sp = p_menu:number_float('Pitch', menu.type.scroll)
    sp:fmt('%.1f', -360.0, 360.0, 1.0)
    sp:tooltip('Tilt forward or back')

    local srl = p_menu:number_float('Roll', menu.type.scroll)
    srl:fmt('%.1f', -360.0, 360.0, 1.0)
    srl:tooltip('Tilt left or right')

    local sy_rot = p_menu:number_float('Yaw', menu.type.scroll)
    sy_rot:fmt('%.1f', -360.0, 360.0, 1.0)
    sy_rot:tooltip('Face left or right')

    --------------------------------------------------------------------
    -- Live update helper
    --------------------------------------------------------------------
    local menu_alive = true

    local function live_update()
        if not menu_alive then return end
        if not attached_vehicle then return end
        if attached_player_name ~= pname then return end
        pcall(do_attach, attached_vehicle,
            sx.value, sy.value, sz.value,
            sp.value, srl.value, sy_rot.value)
    end

    sx:event(menu.event.change, function() live_update() end)
    sy:event(menu.event.change, function() live_update() end)
    sz:event(menu.event.change, function() live_update() end)
    sp:event(menu.event.change, function() live_update() end)
    srl:event(menu.event.change, function() live_update() end)
    sy_rot:event(menu.event.change, function() live_update() end)

    --------------------------------------------------------------------
    -- Presets
    --------------------------------------------------------------------
    p_menu:breaker('Presets')

    for _, preset in ipairs(presets) do
        local btn = p_menu:button(preset[1])
        btn:tooltip(preset[1])
        btn:event(menu.event.click, function()
            if not menu_alive then return end

            local ok_t, target = pcall(players.get, pid)
            if not ok_t or not target then
                safe_notify('Player no longer in session')
                return
            end

            local ok_e, exists = pcall(function() return target.exists end)
            local ok_c, connected = pcall(function() return target.connected end)
            if not (ok_e and exists) or not (ok_c and connected) then
                safe_notify('Player no longer in session')
                return
            end

            local ok_v, in_veh = pcall(function() return target.in_vehicle end)
            local ok_vh, veh = pcall(function() return target.vehicle end)
            if not (ok_v and in_veh) or not (ok_vh and veh) or veh == 0 then
                safe_notify(pname .. ' is not in a vehicle')
                return
            end

            sx.value = preset[2]
            sy.value = preset[3]
            sz.value = preset[4]
            sp.value = preset[5]
            srl.value = preset[6]
            sy_rot.value = preset[7]

            if do_attach(veh, preset[2], preset[3], preset[4], preset[5], preset[6], preset[7]) then
                attached_player_name = pname
                safe_notify('Attached to ' .. pname .. ' (' .. preset[1] .. ')')
            end
        end)
    end

    --------------------------------------------------------------------
    -- Actions
    --------------------------------------------------------------------
    p_menu:breaker('Actions')

    local attach_btn = p_menu:button('Attach')
    attach_btn:tooltip('Attach using the position and rotation values above')
    attach_btn:event(menu.event.click, function()
        if not menu_alive then return end

        local ok_t, target = pcall(players.get, pid)
        if not ok_t or not target then
            safe_notify('Player no longer in session')
            return
        end

        local ok_e, exists = pcall(function() return target.exists end)
        local ok_c, connected = pcall(function() return target.connected end)
        if not (ok_e and exists) or not (ok_c and connected) then
            safe_notify('Player no longer in session')
            return
        end

        -- Use stored pid instead of accessing target.id (metamethod-backed, could throw)
        local ok_me2, my2 = pcall(players.me)
        if ok_me2 and my2 then
            local ok_mid, mid = pcall(function() return my2.id end)
            if ok_mid and mid and pid == mid then
                safe_notify('Cannot attach to yourself')
                return
            end
        end

        local ok_v, in_veh = pcall(function() return target.in_vehicle end)
        local ok_vh, veh = pcall(function() return target.vehicle end)
        if not (ok_v and in_veh) or not (ok_vh and veh) or veh == 0 then
            safe_notify(pname .. ' is not in a vehicle')
            return
        end

        if do_attach(veh, sx.value, sy.value, sz.value, sp.value, srl.value, sy_rot.value) then
            attached_player_name = pname
            safe_notify('Attached to ' .. attached_player_name)
        end
    end)

    local detach_btn2 = p_menu:button('Detach')
    detach_btn2:tooltip('Detach from this player\'s vehicle')
    detach_btn2:event(menu.event.click, function()
        if attached_vehicle then
            do_detach()
            safe_notify('Detached')
        else
            safe_notify('Not attached to anything')
        end
    end)

    local reset_btn = p_menu:button('Reset Sliders')
    reset_btn:tooltip('Reset all position and rotation sliders to 0')
    reset_btn:event(menu.event.click, function()
        if not menu_alive then return end
        sx.value = 0.0
        sy.value = 0.0
        sz.value = 0.0
        sp.value = 0.0
        srl.value = 0.0
        sy_rot.value = 0.0
        live_update()
        safe_notify('Sliders reset')
    end)

    local col_toggle = p_menu:toggle('Disable Collision')
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

    -- Return cleanup function to invalidate callbacks when menu is rebuilt
    return function()
        menu_alive = false
    end
end

-----------------------------------------------------------------------
-- Build / rebuild player list
-- ONLY called from coroutine threads — never from callbacks directly.
-----------------------------------------------------------------------
local menu_cleanup_fns = {}

local function rebuild_player_list()
    -- Invalidate all old menu callbacks
    for _, cleanup in ipairs(menu_cleanup_fns) do
        pcall(cleanup)
    end
    menu_cleanup_fns = {}

    -- Delete old player submenus
    for _, m in ipairs(player_menus) do
        safe_delete_menu(m)
    end
    player_menus = {}

    -- Yield to let the menu engine process deletions (safe — we're in a thread)
    util.yield(100)

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

    local count = 0
    for _, player in ipairs(player_list) do
        local p_ok, p_conn, p_exists, p_id = pcall(function()
            return player.connected, player.exists, player.id
        end)
        if p_ok and p_conn and p_exists and p_id ~= my_id then
            local ok2, cleanup = pcall(add_player_menu, player)
            if ok2 and cleanup then
                count = count + 1
                table.insert(menu_cleanup_fns, cleanup)
            end
        end
    end

    safe_notify('Found ' .. count .. ' players')
end

-----------------------------------------------------------------------
-- Single rebuild thread — all rebuilds happen here (coroutine-safe).
-- Debounces by waiting 500ms, then checking the flag.
-----------------------------------------------------------------------
util.create_thread(function()
    while true do
        util.yield(500)
        if rebuild_requested then
            rebuild_requested = false
            pcall(rebuild_player_list)
        end
    end
end)

-----------------------------------------------------------------------
-- Auto-refresh on player join/leave
-----------------------------------------------------------------------
pcall(function()
    events.subscribe(events.event.player_join, function(data)
        request_rebuild()
    end)
end)

pcall(function()
    events.subscribe(events.event.player_leave, function(data)
        -- Check if the leaving player is who we're attached to
        local left_name = nil
        if data and type(data) == 'table' then
            if data.player and type(data.player) == 'table' and data.player.name then
                left_name = tostring(data.player.name)
            elseif data.name then
                left_name = tostring(data.name)
            end
        end

        if attached_player_name and left_name and left_name == attached_player_name then
            do_detach()
            safe_notify('Auto-detached: ' .. left_name .. ' left', { icon = notify.icon.hazard })
        end

        request_rebuild()
    end)
end)

-----------------------------------------------------------------------
-- Initial build + startup
-----------------------------------------------------------------------
util.create_thread(function()
    util.yield(2000)
    pcall(rebuild_player_list)
end)

safe_notify('v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
