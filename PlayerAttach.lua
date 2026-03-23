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
local SCRIPT_VERSION = '1.2.0'

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
local N_IS_ENTITY_ATTACHED_TO_ENTITY           = 0xEFBE71898A993728
local N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION = 0x1A9205C1B9EE827F
local N_DOES_ENTITY_EXIST                      = 0x7239B21A38F536BA
local N_SET_ENTITY_INVINCIBLE                  = 0x3882114BDE571AD4

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
    { 'Roof',        0.0,   0.0,  1.2,  0.0, 0.0,   0.0 },
    { 'Hood',        0.0,   2.5,  0.8,  0.0, 0.0,   0.0 },
    { 'Trunk',       0.0,  -2.5,  0.8,  0.0, 0.0, 180.0 },
    { 'Left Side',  -1.2,   0.0,  0.5,  0.0, 0.0, -90.0 },
    { 'Right Side',  1.2,   0.0,  0.5,  0.0, 0.0,  90.0 },
    { 'Hanging Back', 0.0, -2.0,  0.2, 0.0, 0.0, 180.0 },
}

-----------------------------------------------------------------------
-- Safe native call wrapper
-----------------------------------------------------------------------
local function safe_call(...)
    local ok, result = pcall(invoker.call, ...)
    if ok then
        return result
    end
    return nil
end

-----------------------------------------------------------------------
-- Entity helpers
-----------------------------------------------------------------------
local function entity_exists(handle)
    if not handle or handle == 0 then
        return false
    end
    local result = safe_call(N_DOES_ENTITY_EXIST, handle)
    if result then
        return result.bool
    end
    return false
end

local function get_my_entity()
    local me = players.me()
    if not me then
        return nil
    end
    if me.in_vehicle and me.vehicle ~= 0 then
        return me.vehicle
    elseif me.ped ~= 0 then
        return me.ped
    end
    return nil
end

local function is_entity_attached(entity)
    if not entity then return false end
    local result = safe_call(N_IS_ENTITY_ATTACHED, entity)
    if result then
        return result.bool
    end
    return false
end

-----------------------------------------------------------------------
-- Core attach (raw, no notifications)
-----------------------------------------------------------------------
local function raw_attach(entity, target_vehicle, x, y, z, pitch, roll, yaw)
    safe_call(N_ATTACH_ENTITY_TO_ENTITY,
        entity,
        target_vehicle,
        0,                  -- boneIndex: 0 = center
        x, y, z,            -- position offset
        pitch, roll, yaw,   -- rotation offset (all 3 axes)
        1,                  -- p9
        0,                  -- useSoftPinning: 0 = won't detach
        1,                  -- collision
        0,                  -- isPed
        0,                  -- rotationOrder
        1                   -- syncRot
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
        safe_call(N_DETACH_ENTITY, entity, 1, 1)
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
        safe_call(N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, 0, 0)
    end

    return true
end

local function do_detach()
    -- Stop the re-attach loop from fighting us
    attach_params.active = false
    attach_params.vehicle = nil

    local entity = get_my_entity()
    if entity and is_entity_attached(entity) then
        safe_call(N_DETACH_ENTITY, entity, 1, 1)
    end

    attached_vehicle = nil
    attached_player_name = nil
end

-----------------------------------------------------------------------
-- Persistent re-attach thread
-- Keeps you attached even when animations, ragdoll, etc try to detach
-----------------------------------------------------------------------
util.create_thread(function()
    while true do
        if attach_params.active and attach_params.vehicle then
            local entity = get_my_entity()
            if entity and entity_exists(attach_params.vehicle) then
                if not is_entity_attached(entity) then
                    -- We got detached (animation, ragdoll, etc) - reattach
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
                        safe_call(N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, 0, 0)
                    end
                end
            elseif attach_params.vehicle and not entity_exists(attach_params.vehicle) then
                -- Vehicle is gone, clean up
                attach_params.active = false
                attach_params.vehicle = nil
                attached_vehicle = nil
                attached_player_name = nil
                notify.push(SCRIPT_NAME, 'Vehicle no longer exists, detached', { icon = notify.icon.hazard })
            end
        end
        util.yield()
    end
end)

-----------------------------------------------------------------------
-- Menu setup
-----------------------------------------------------------------------
local root = menu.root()
local player_menus = {} -- track created player submenus for cleanup

-----------------------------------------------------------------------
-- Quick detach + refresh at top
-----------------------------------------------------------------------
root:button('Detach')
    :tooltip('Quick detach from any vehicle you are attached to')
    :event(menu.event.click, function()
        if attached_vehicle then
            local name = attached_player_name or 'vehicle'
            do_detach()
            notify.push(SCRIPT_NAME, 'Detached from ' .. name)
        else
            notify.push(SCRIPT_NAME, 'Not attached to anything')
        end
    end)

root:button('Refresh Players')
    :tooltip('Refresh the player list below')
    :event(menu.event.click, function()
        rebuild_player_list()
    end)

-----------------------------------------------------------------------
-- Build a full submenu for one player with ALL settings inside
-----------------------------------------------------------------------
local function add_player_menu(player)
    if player.id == players.me().id then
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
    -- Position
    --------------------------------------------------------------------
    p_menu:breaker('Position')

    local sx = p_menu:number_float('Left / Right', menu.type.scroll)
        :fmt('%.2f', -15.0, 15.0, 0.05)
        :tooltip('Left or right')

    local sy = p_menu:number_float('Front / Back', menu.type.scroll)
        :fmt('%.2f', -15.0, 15.0, 0.05)
        :tooltip('Front or back')

    local sz = p_menu:number_float('Up / Down', menu.type.scroll)
        :fmt('%.2f', -15.0, 15.0, 0.05)
        :tooltip('Up or down')

    --------------------------------------------------------------------
    -- Rotation
    --------------------------------------------------------------------
    p_menu:breaker('Rotation')

    local sp = p_menu:number_float('Pitch', menu.type.scroll)
        :fmt('%.1f', -360.0, 360.0, 1.0)
        :tooltip('Tilt forward or back')

    local srl = p_menu:number_float('Roll', menu.type.scroll)
        :fmt('%.1f', -360.0, 360.0, 1.0)
        :tooltip('Tilt left or right')

    local sy_rot = p_menu:number_float('Yaw', menu.type.scroll)
        :fmt('%.1f', -360.0, 360.0, 1.0)
        :tooltip('Face left or right')

    --------------------------------------------------------------------
    -- Helper to get all current values and re-attach
    --------------------------------------------------------------------
    local function live_update()
        if attached_vehicle and attached_player_name == pname then
            do_attach(attached_vehicle, sx.value, sy.value, sz.value, sp.value, srl.value, sy_rot.value)
        end
    end

    -- Live update on any slider change
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

    for i, preset in ipairs(presets) do
        p_menu:button(preset[1])
            :tooltip(preset[1])
            :event(menu.event.click, function()
                local target = players.get(pid)
                if not target or not target.exists or not target.connected then
                    notify.push(SCRIPT_NAME, 'Player no longer in session')
                    return
                end
                if not target.in_vehicle or target.vehicle == 0 then
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

    p_menu:button('Attach')
        :tooltip('Attach using the position and rotation values above')
        :event(menu.event.click, function()
            local target = players.get(pid)
            if not target or not target.exists or not target.connected then
                notify.push(SCRIPT_NAME, 'Player no longer in session')
                return
            end
            if target.id == players.me().id then
                notify.push(SCRIPT_NAME, 'Cannot attach to yourself')
                return
            end
            if not target.in_vehicle or target.vehicle == 0 then
                notify.push(SCRIPT_NAME, target.name .. ' is not in a vehicle')
                return
            end

            if do_attach(target.vehicle, sx.value, sy.value, sz.value, sp.value, srl.value, sy_rot.value) then
                attached_player_name = target.name
                notify.push(SCRIPT_NAME, 'Attached to ' .. target.name)
            end
        end)

    p_menu:button('Detach')
        :tooltip('Detach from this player\'s vehicle')
        :event(menu.event.click, function()
            if attached_vehicle then
                do_detach()
                notify.push(SCRIPT_NAME, 'Detached')
            else
                notify.push(SCRIPT_NAME, 'Not attached to anything')
            end
        end)

    p_menu:button('Reset Sliders')
        :tooltip('Reset all position and rotation sliders to 0')
        :event(menu.event.click, function()
            sx.value = 0.0
            sy.value = 0.0
            sz.value = 0.0
            sp.value = 0.0
            srl.value = 0.0
            sy_rot.value = 0.0
            live_update()
            notify.push(SCRIPT_NAME, 'Sliders reset')
        end)

    p_menu:toggle('Disable Collision')
        :tooltip('Clip through the vehicle instead of colliding with it')
        :event(menu.event.change, function(val)
            collision_disabled = val
            if attached_vehicle and collision_disabled then
                local entity = get_my_entity()
                if entity then
                    safe_call(N_SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, 0, 0)
                end
                notify.push(SCRIPT_NAME, 'Collision disabled')
            end
        end)
end

-----------------------------------------------------------------------
-- Build / rebuild the full player list at root level
-----------------------------------------------------------------------
function rebuild_player_list()
    -- Delete all existing player submenus
    for _, m in ipairs(player_menus) do
        pcall(function() m:delete() end)
    end
    player_menus = {}

    local ok, player_list = pcall(players.list)
    if not ok or not player_list then
        notify.push(SCRIPT_NAME, 'Could not get player list')
        return
    end

    local count = 0
    for _, player in ipairs(player_list) do
        if player.connected and player.exists and player.id ~= players.me().id then
            local ok2 = pcall(add_player_menu, player)
            if ok2 then
                count = count + 1
            end
        end
    end

    notify.push(SCRIPT_NAME, 'Found ' .. count .. ' players')
end

-----------------------------------------------------------------------
-- Auto-refresh on player join/leave
-----------------------------------------------------------------------
events.subscribe(events.event.player_join, function(data)
    rebuild_player_list()
end)

events.subscribe(events.event.player_leave, function(data)
    local left_name = nil
    if data then
        if data.player and data.player.name then
            left_name = data.player.name
        elseif data.name then
            left_name = data.name
        end
    end

    if attached_player_name and left_name and left_name == attached_player_name then
        do_detach()
        notify.push(SCRIPT_NAME, 'Auto-detached: ' .. left_name .. ' left', { icon = notify.icon.hazard })
    end

    rebuild_player_list()
end)

-----------------------------------------------------------------------
-- Initial build + startup
-----------------------------------------------------------------------
util.create_thread(function()
    util.yield(2000)
    rebuild_player_list()
end)

notify.push(SCRIPT_NAME, 'v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
