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
local SCRIPT_VERSION = '1.0.0'

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
local ATTACH_ENTITY_TO_ENTITY                 = 0x6B9BBD38AB0796DF
local DETACH_ENTITY                           = 0x961AC54BF0613F5D
local IS_ENTITY_ATTACHED                      = 0xB346476EF1A64897
local IS_ENTITY_ATTACHED_TO_ENTITY            = 0xEFBE71898A993728
local SET_ENTITY_COMPLETELY_DISABLE_COLLISION  = 0x1A9205C1B9EE827F

-----------------------------------------------------------------------
-- State
-----------------------------------------------------------------------
local attached_vehicle = nil
local attached_player_name = nil
local collision_disabled = false

-----------------------------------------------------------------------
-- Preset positions
-----------------------------------------------------------------------
local presets = {
    { 'Roof',        0.0,   0.0,  1.2,   0.0 },
    { 'Hood',        0.0,   2.5,  0.8,   0.0 },
    { 'Trunk',       0.0,  -2.5,  0.8, 180.0 },
    { 'Left Side',  -1.2,   0.0,  0.5, 270.0 },
    { 'Right Side',  1.2,   0.0,  0.5,  90.0 },
}

-----------------------------------------------------------------------
-- Core functions
-----------------------------------------------------------------------

local function get_my_entity()
    local me = players.me()
    if me.in_vehicle then
        return me.vehicle
    else
        return me.ped
    end
end

local function do_attach(target_vehicle, x, y, z, rot)
    local entity = get_my_entity()

    -- Detach first if already attached (for live repositioning)
    if invoker.call(IS_ENTITY_ATTACHED_TO_ENTITY, entity, target_vehicle).bool then
        invoker.call(DETACH_ENTITY, entity, true, true)
    end

    -- Attach to the target vehicle center (bone 0)
    invoker.call(ATTACH_ENTITY_TO_ENTITY,
        entity,             -- entity1: our ped or vehicle
        target_vehicle,     -- entity2: their vehicle
        0,                  -- boneIndex: 0 = center
        x, y, z,            -- position offset (local coords)
        0.0, 0.0, rot,      -- rotation offset (only Z exposed)
        true,               -- p9
        false,              -- useSoftPinning: false = won't detach
        true,               -- collision: true = keep collision
        false,              -- isPed
        0,                  -- rotationOrder
        true                -- syncRot
    )

    attached_vehicle = target_vehicle

    if collision_disabled then
        invoker.call(SET_ENTITY_COMPLETELY_DISABLE_COLLISION, entity, false, false)
    end
end

local function do_detach()
    local me = players.me()

    if me.in_vehicle then
        if invoker.call(IS_ENTITY_ATTACHED, me.vehicle).bool then
            invoker.call(DETACH_ENTITY, me.vehicle, true, true)
        end
    else
        if invoker.call(IS_ENTITY_ATTACHED, me.ped).bool then
            invoker.call(DETACH_ENTITY, me.ped, true, true)
        end
    end

    attached_vehicle = nil
    attached_player_name = nil
end

-----------------------------------------------------------------------
-- Menu setup
-----------------------------------------------------------------------
local root = menu.root()
local BASE_SIZE = 2 -- refresh button + breaker

-----------------------------------------------------------------------
-- Quick detach at top (only thing at root besides player list)
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
    local pid = player.id

    --------------------------------------------------------------------
    -- Position sliders (per-player, all inside this player's menu)
    --------------------------------------------------------------------
    p_menu:breaker('Position Offset')

    local sx = p_menu:number_float('Left / Right', menu.type.scroll)
        :fmt('%.2f', -10.0, 10.0, 0.10)
        :tooltip('- Left / + Right')

    local sy = p_menu:number_float('Back / Forward', menu.type.scroll)
        :fmt('%.2f', -10.0, 10.0, 0.10)
        :tooltip('- Backward / + Forward')

    local sz = p_menu:number_float('Down / Up', menu.type.scroll)
        :fmt('%.2f', -10.0, 10.0, 0.10)
        :tooltip('- Down / + Up')

    local sr = p_menu:number_float('Rotation', menu.type.scroll)
        :fmt('%.0f', 0.0, 359.0, 1.0)
        :tooltip('Rotate your character (degrees)')

    -- Live update: when any slider changes and we're attached, reposition
    sx:event(menu.event.click, function(opt)
        if attached_vehicle and attached_player_name == player.name then
            do_attach(attached_vehicle, opt.value, sy.value, sz.value, sr.value)
        end
    end)

    sy:event(menu.event.click, function(opt)
        if attached_vehicle and attached_player_name == player.name then
            do_attach(attached_vehicle, sx.value, opt.value, sz.value, sr.value)
        end
    end)

    sz:event(menu.event.click, function(opt)
        if attached_vehicle and attached_player_name == player.name then
            do_attach(attached_vehicle, sx.value, sy.value, opt.value, sr.value)
        end
    end)

    sr:event(menu.event.click, function(opt)
        if attached_vehicle and attached_player_name == player.name then
            do_attach(attached_vehicle, sx.value, sy.value, sz.value, opt.value)
        end
    end)

    --------------------------------------------------------------------
    -- Presets
    --------------------------------------------------------------------
    p_menu:breaker('Presets')

    for i, preset in ipairs(presets) do
        p_menu:button(preset[1])
            :tooltip('Attach to ' .. preset[1] .. ' of their vehicle')
            :event(menu.event.click, function()
                local target = players.get(pid)
                if not target or not target.exists or not target.connected then
                    notify.push(SCRIPT_NAME, 'Player no longer in session')
                    return
                end
                if not target.in_vehicle then
                    notify.push(SCRIPT_NAME, target.name .. ' is not in a vehicle')
                    return
                end

                sx.value = preset[2]
                sy.value = preset[3]
                sz.value = preset[4]
                sr.value = preset[5]

                do_attach(target.vehicle, preset[2], preset[3], preset[4], preset[5])
                attached_player_name = target.name
                notify.push(SCRIPT_NAME, 'Attached to ' .. target.name .. ' (' .. preset[1] .. ')')
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
            if not target.in_vehicle then
                notify.push(SCRIPT_NAME, target.name .. ' is not in a vehicle')
                return
            end

            do_attach(target.vehicle, sx.value, sy.value, sz.value, sr.value)
            attached_player_name = target.name
            notify.push(SCRIPT_NAME, 'Attached to ' .. target.name)
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

    p_menu:toggle('Disable Collision')
        :tooltip('Clip through the vehicle instead of colliding with it')
        :event(menu.event.click, function(opt)
            collision_disabled = opt.value
            if attached_vehicle and collision_disabled then
                invoker.call(SET_ENTITY_COMPLETELY_DISABLE_COLLISION, get_my_entity(), false, false)
                notify.push(SCRIPT_NAME, 'Collision disabled')
            end
        end)
end

-----------------------------------------------------------------------
-- Build / rebuild the full player list at root level
-----------------------------------------------------------------------
function rebuild_player_list()
    root:resize(BASE_SIZE)

    local player_list = players.list()
    local count = 0

    for _, player in ipairs(player_list) do
        if player.connected and player.exists and player.id ~= players.me().id then
            add_player_menu(player)
            count = count + 1
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
    if attached_player_name and data.player.name == attached_player_name then
        do_detach()
        notify.push(SCRIPT_NAME, 'Auto-detached: ' .. data.player.name .. ' left', { icon = notify.icon.hazard })
    end

    rebuild_player_list()
end)

-----------------------------------------------------------------------
-- Initial build + startup
-----------------------------------------------------------------------
util.create_job(function()
    util.yield(1000)
    rebuild_player_list()
end)

notify.push(SCRIPT_NAME, 'v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
