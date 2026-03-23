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
local ATTACH_ENTITY_TO_ENTITY      = 0x6B9BBD38AB0796DF
local DETACH_ENTITY                 = 0x961AC54BF0613F5D
local IS_ENTITY_ATTACHED            = 0xB346476EF1A64897
local IS_ENTITY_ATTACHED_TO_ENTITY  = 0xEFBE71898A993728
local SET_ENTITY_COMPLETELY_DISABLE_COLLISION = 0x1A9205C1B9EE827F

-----------------------------------------------------------------------
-- State
-----------------------------------------------------------------------
local attached_vehicle = nil
local attached_player_name = nil

-----------------------------------------------------------------------
-- Core functions
-----------------------------------------------------------------------

--- Returns our ped or vehicle handle depending on if we're in a vehicle
local function get_my_entity()
    local me = players.me()
    if me.in_vehicle then
        return me.vehicle
    else
        return me.ped
    end
end

--- Attach our local entity to a target vehicle with given offsets
local function do_attach(target_vehicle, x, y, z, rot)
    local entity = get_my_entity()

    -- Detach first if already attached to this vehicle (for live repositioning)
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
end

--- Detach our local entity from whatever it's attached to
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
-- Menu: Root (quick detach access)
-----------------------------------------------------------------------
local root = menu.root()

root:button('Detach From Vehicle')
    :tooltip('Detach from any vehicle you are currently attached to')
    :event(menu.event.click, function()
        if attached_vehicle then
            do_detach()
            notify.push(SCRIPT_NAME, 'Detached')
        else
            notify.push(SCRIPT_NAME, 'Not attached to anything')
        end
    end)

root:toggle('Disable Collision')
    :tooltip('Disable collision with the attached vehicle so you clip through it')
    :event(menu.event.click, function(opt)
        if attached_vehicle and opt.value then
            invoker.call(SET_ENTITY_COMPLETELY_DISABLE_COLLISION, get_my_entity(), false, false)
            notify.push(SCRIPT_NAME, 'Collision disabled')
        end
    end)

-----------------------------------------------------------------------
-- Menu: Player Root (per-player attach options)
-----------------------------------------------------------------------
local player_root = menu.player_root()

local attach_menu = player_root:submenu('Attach To Vehicle')

attach_menu:breaker('Position Offset')

local slider_x = attach_menu:number_float('Left / Right', menu.type.scroll)
    :fmt('%.2f', -10.0, 10.0, 0.10)
    :tooltip('- Left / + Right')
    :event(menu.event.click, function(opt)
        if attached_vehicle then
            do_attach(attached_vehicle, opt.value, slider_y.value, slider_z.value, slider_rot.value)
        end
    end)

local slider_y = attach_menu:number_float('Back / Forward', menu.type.scroll)
    :fmt('%.2f', -10.0, 10.0, 0.10)
    :tooltip('- Backward / + Forward')
    :event(menu.event.click, function(opt)
        if attached_vehicle then
            do_attach(attached_vehicle, slider_x.value, opt.value, slider_z.value, slider_rot.value)
        end
    end)

local slider_z = attach_menu:number_float('Down / Up', menu.type.scroll)
    :fmt('%.2f', -10.0, 10.0, 0.10)
    :tooltip('- Down / + Up')
    :event(menu.event.click, function(opt)
        if attached_vehicle then
            do_attach(attached_vehicle, slider_x.value, slider_y.value, opt.value, slider_rot.value)
        end
    end)

attach_menu:breaker('Rotation')

local slider_rot = attach_menu:number_float('Rotation', menu.type.scroll)
    :fmt('%.0f', 0.0, 359.0, 1.0)
    :tooltip('Rotate your character (degrees)')
    :event(menu.event.click, function(opt)
        if attached_vehicle then
            do_attach(attached_vehicle, slider_x.value, slider_y.value, slider_z.value, opt.value)
        end
    end)

attach_menu:breaker('Actions')

-----------------------------------------------------------------------
-- Preset positions
-----------------------------------------------------------------------
local presets = {
    { 'Roof',       0.0,  0.0,  1.2,  0.0 },
    { 'Hood',       0.0,  2.5,  0.8,  0.0 },
    { 'Trunk',      0.0, -2.5,  0.8, 180.0 },
    { 'Left Side',  -1.2, 0.0,  0.5, 270.0 },
    { 'Right Side',  1.2, 0.0,  0.5,  90.0 },
}

local preset_values = {}
for i, p in ipairs(presets) do
    preset_values[i] = { p[1], i }
end

attach_menu:combo_int('Presets', preset_values, menu.type.press)
    :tooltip('Quick attach to a preset position')
    :event(menu.event.click, function(opt)
        local target = players.target()

        if players.is_target_session() then
            notify.push(SCRIPT_NAME, 'Select a player, not the session')
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

        local preset = presets[opt.value]
        if preset then
            slider_x.value = preset[2]
            slider_y.value = preset[3]
            slider_z.value = preset[4]
            slider_rot.value = preset[5]
            do_attach(target.vehicle, preset[2], preset[3], preset[4], preset[5])
            attached_player_name = target.name
            notify.push(SCRIPT_NAME, 'Attached to ' .. target.name .. ' (' .. preset[1] .. ')')
        end
    end)

-----------------------------------------------------------------------
-- Attach / Detach buttons
-----------------------------------------------------------------------
attach_menu:button('Attach')
    :tooltip('Attach to the selected player\'s vehicle')
    :event(menu.event.click, function()
        local target = players.target()

        if players.is_target_session() then
            notify.push(SCRIPT_NAME, 'Select a player, not the session')
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

        do_attach(target.vehicle, slider_x.value, slider_y.value, slider_z.value, slider_rot.value)
        attached_player_name = target.name
        notify.push(SCRIPT_NAME, 'Attached to ' .. target.name)
    end)

attach_menu:button('Detach')
    :tooltip('Detach from the vehicle')
    :event(menu.event.click, function()
        if attached_vehicle then
            local name = attached_player_name or 'vehicle'
            do_detach()
            notify.push(SCRIPT_NAME, 'Detached from ' .. name)
        else
            notify.push(SCRIPT_NAME, 'Not attached to anything')
        end
    end)

-----------------------------------------------------------------------
-- Auto-detach if the target player leaves
-----------------------------------------------------------------------
events.subscribe(events.event.player_leave, function(data)
    if attached_player_name and data.player.name == attached_player_name then
        do_detach()
        notify.push(SCRIPT_NAME, 'Auto-detached: ' .. data.player.name .. ' left the session')
    end
end)

-----------------------------------------------------------------------
-- Startup
-----------------------------------------------------------------------
notify.push(SCRIPT_NAME, 'v' .. SCRIPT_VERSION .. ' loaded', { icon = notify.icon.info })
