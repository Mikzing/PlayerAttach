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
local SCRIPT_VERSION = '1.3.0'

-----------------------------------------------------------------------
-- Permission check
-----------------------------------------------------------------------
if this.permissions() & permission.natives == 0 then
    notify.push(SCRIPT_NAME, 'Natives permission required. Exiting.', { icon = notify.icon.hazard })
    this.unload()
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
    -- Handle table-like returns (some menu versions return { bool = ..., int = ... })
    if t == 'table' then
        if result.bool ~= nil then
            return result.bool
        end
        if result.int ~= nil then
            return result.int ~= 0
        end
        return false
    end
    -- Handle userdata / cdata: try common accessors safely
    if t == 'userdata' or t == 'cdata' then
        local ok1, val1 = pcall(function() return result:__tointeger() end)
        if ok1 and val1 ~= nil then return val1 ~= 0 end
        local ok2, val2 = pcall(function() return result.bool end)
        if ok2 and type(val2) == 'boolean' then return val2 end
        local ok3, val3 = pcall(function() return result.int end)
        if ok3 and type(val3) == 'number' then return val3 ~= 0 end
        local ok4, val4 = pcall(function() return tonumber(result) end)
        if ok4 and val4 ~= nil then return val4 ~= 0 end
        return false
    end
    return false
end

-----------------------------------------------------------------------
-- State
-----------------------------------------------------------------------
local attached_vehicle = nil
local attached_player_name = nil
local collision_disabled = false
local rebuild_pending = false

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
    if me.in_vehicle and me.vehicle and me.vehicle ~= 0 then
        return me.vehicle
    end
    if me.ped and me.ped ~= 0 then
        return me.ped
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
-- Core attach (raw, no notifications)
-----------------------------------------------------------------------
local function raw_attach(entity, target_vehicle, x, y, z, pitch, roll, yaw)
    -- Ensure float params are actual floats by adding 0.0
    call_native(N_ATTACH_ENTITY_TO_ENTITY,
        entity,
        target_vehicle,
        0,                              -- boneIndex (int)
        x + 0.0, y + 0.0, z + 0.0,    -- position offset (float)
        pitch + 0.0, roll + 0.0, yaw + 0.0, -- rotation offset (float)
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
-----------------------------------------------------------------------
local function do_attach(target_vehicle, x, y, z, pitch, roll, yaw)
    local entity = get_my_entity()
    if not entity then
        notify.push(SCRIPT_NAME, 'Could not get your entity')
        return false
    end

    if not entity_exists(target_vehicle) then
        notify.push(SCRIPT_NAME, 'Target vehicle no longer exists')
        return false
    end

    -- Detach first if already attached (for live repositioning)
    if is_entity_attached(entity) then
        call_native(N_DETACH_ENTITY, entity, 1, 1)
        util.yield(50)  -- brief pause to let the engine process detach
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
-----------------------------------------------------------------------
util.create_thread(function()
    while true do
        util.yield(200)  -- throttle: check 5 times per second, not every frame

        if not attach_params.active or not attach_params.vehicle then
            goto continue
        end

        local entity = get_my_entity()
        if not entity then
            goto continue
        end

        if not entity_exists(attach_params.vehicle) then
            -- Target vehicle is gone, clean up
            attach_params.active = false
            attach_params.vehicle = nil
            attached_vehicle = nil
            attached_player_name = nil
            pcall(notify.push, SCRIPT_NAME, 'Vehicle no longer exists, detached', { icon = notify.icon.hazard })
            goto continue
        end

        if not is_entity_attached(entity) then
            -- We got detached (animation, ragdoll, etc) — reattach
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
local player_menus = {}  -- track created player submenu handles

-----------------------------------------------------------------------
-- Safe menu helpers
-----------------------------------------------------------------------
local function safe_delete_menu(m)
    if not m then return end
    -- Try multiple deletion methods — API varies between versions
    local ok = pcall(function() m:delete() end)
    if not ok then
        pcall(function() m:remove() end)
    end
end

-----------------------------------------------------------------------
-- Quick detach + refresh at top
-----------------------------------------------------------------------
local detach_btn = root:button('Detach')
detach_btn:tooltip('Quick detach from any vehicle you are attached to')
detach_btn:event(menu.event.click, function()
    if attached_vehicle then
        local name = attached_player_name or 'vehicle'
        do_detach()
        notify.push(SCRIPT_NAME, 'Detached from ' .. name)
    else
        notify.push(SCRIPT_NAME, 'Not attached to anything')
    end
end)

local refresh_btn = root:button('Refresh Players')
refresh_btn:tooltip('Refresh the player list below')
refresh_btn:event(menu.event.click, function()
    rebuild_player_list()
end)

-----------------------------------------------------------------------
-- Build a full submenu for one player
-----------------------------------------------------------------------
local function add_player_menu(player)
    local my = players.me()
    if not my or player.id == my.id then
        return
    end

    local label = player.name
    if not player.in_vehicle then
        label = label .. ' [On Foot]'
    end

    local p_menu = root:submenu(label)
    table.insert(player_menus, p_menu)

    local pid = player.id
    local pname = player.name

    --------------------------------------------------------------------
    -- Position (avoid chaining — assign each step to avoid crashes
    -- if an intermediate method returns nil)
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
    -- Live update helper — only acts if we are attached to THIS player
    --------------------------------------------------------------------
    local menu_alive = true  -- guard against callbacks firing after rebuild

    local function live_update()
        if not menu_alive then return end
        if attached_vehicle and attached_player_name == pname then
            pcall(do_attach, attached_vehicle,
                sx.value, sy.value, sz.value,
                sp.value, srl.value, sy_rot.value)
        end
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
            local ok, target = pcall(players.get, pid)
            if not ok or not target or not target.exists or not target.connected then
                notify.push(SCRIPT_NAME, 'Player no longer in session')
                return
            end
            if not target.in_vehicle or not target.vehicle or target.vehicle == 0 then
                notify.push(SCRIPT_NAME, target.name .. ' is not in a vehicle')
                return
            end

            sx.value = preset[2]
            sy.value = preset[3]
            sz.value = preset[4]
            sp.value = preset[5]
            srl.value = preset[6]
            sy_rot.value = preset[7]

            if do_attach(target.vehicle, preset[2], preset[3], preset[4], preset[5], preset[6], preset[7]) then
                attached_player_name = target.name
                notify.push(SCRIPT_NAME, 'Attached to ' .. target.name .. ' (' .. preset[1] .. ')')
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
        local ok, target = pcall(players.get, pid)
        if not ok or not target or not target.exists or not target.connected then
            notify.push(SCRIPT_NAME, 'Player no longer in session')
            return
        end
        local my = players.me()
        if my and target.id == my.id then
            notify.push(SCRIPT_NAME, 'Cannot attach to yourself')
            return
        end
        if not target.in_vehicle or not target.vehicle or target.vehicle == 0 then
            notify.push(SCRIPT_NAME, target.name .. ' is not in a vehicle')
            return
        end

        if do_attach(target.vehicle, sx.value, sy.value, sz.value, sp.value, srl.value, sy_rot.value) then
            attached_player_name = target.name
            notify.push(SCRIPT_NAME, 'Attached to ' .. target.name)
        end
    end)

    local detach_btn2 = p_menu:button('Detach')
    detach_btn2:tooltip('Detach from this player\'s vehicle')
    detach_btn2:event(menu.event.click, function()
        if attached_vehicle then
            do_detach()
            notify.push(SCRIPT_NAME, 'Detached')
        else
            notify.push(SCRIPT_NAME, 'Not attached to anything')
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
        notify.push(SCRIPT_NAME, 'Sliders reset')
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
            notify.push(SCRIPT_NAME, 'Collision disabled')
        end
    end)

    -- Return a cleanup function to invalidate callbacks
    return function()
        menu_alive = false
    end
end

-----------------------------------------------------------------------
-- Build / rebuild player list (with debounce guard)
-----------------------------------------------------------------------
local menu_cleanup_fns = {}

function rebuild_player_list()
    if rebuild_pending then
        return
    end
    rebuild_pending = true

    -- Invalidate all old menu callbacks first
    for _, cleanup in ipairs(menu_cleanup_fns) do
        pcall(cleanup)
    end
    menu_cleanup_fns = {}

    -- Delete old player submenus
    for _, m in ipairs(player_menus) do
        safe_delete_menu(m)
    end
    player_menus = {}

    -- Small yield to let the menu engine process deletions
    util.yield(100)

    local ok, player_list = pcall(players.list)
    if not ok or not player_list then
        rebuild_pending = false
        notify.push(SCRIPT_NAME, 'Could not get player list')
        return
    end

    local my = players.me()
    local my_id = my and my.id or -1

    local count = 0
    for _, player in ipairs(player_list) do
        if player.connected and player.exists and player.id ~= my_id then
            local ok2, cleanup = pcall(add_player_menu, player)
            if ok2 then
                count = count + 1
                if cleanup then
                    table.insert(menu_cleanup_fns, cleanup)
                end
            end
        end
    end

    rebuild_pending = false
    notify.push(SCRIPT_NAME, 'Found ' .. count .. ' players')
end

-----------------------------------------------------------------------
-- Auto-refresh on player join/leave (debounced via thread)
-----------------------------------------------------------------------
local rebuild_requested = false

local function request_rebuild()
    rebuild_requested = true
end

-- Debounce thread: waits 500ms after last request before rebuilding
util.create_thread(function()
    while true do
        util.yield(500)
        if rebuild_requested then
            rebuild_requested = false
            pcall(rebuild_player_list)
        end
    end
end)

events.subscribe(events.event.player_join, function(data)
    request_rebuild()
end)

events.subscribe(events.event.player_leave, function(data)
    -- Check if the leaving player is who we're attached to
    local left_name = nil
    if data then
        if type(data) == 'table' then
            if data.player and data.player.name then
                left_name = data.player.name
            elseif data.name then
                left_name = data.name
            end
        end
    end

    if attached_player_name and left_name and left_name == attached_player_name then
        do_detach()
        pcall(notify.push, SCRIPT_NAME, 'Auto-detached: ' .. left_name .. ' left', { icon = notify.icon.hazard })
    end

    request_rebuild()
end)

-----------------------------------------------------------------------
-- Initial build + startup
-----------------------------------------------------------------------
util.create_thread(function()
    util.yield(2000)
    pcall(rebuild_player_list)
end)

notify.push(SCRIPT_NAME, 'v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
