local event_handler = require("control-event-handler")
local general_util = require("research-challenges-util.general-util")
local time_limits = require("time-limit-constants")

-- Declarations
local update_force_GUI

local function init_handler(event)
    global.cached_research_time_limits = {}
    global.research_time_limit_GUIs = {}
end

local handler_name_research_timer_expired = "research_timer_expired"
-- FIXME 'event' is stored in global table and saved - this might be safe, but I need to verify that.
local function handler_factory_research_timer_expired(event)
    return function(nth_tick_event)
        if event.research.valid and event.research.force.valid then
            local force = event.research.force
            if event.research.name == force.current_research.name then
                force.research_progress = 0
                force.cancel_current_research()
            else
                force.set_saved_technology_progress(event.research, 0)
            end
            update_force_GUI(force.name)
        end
    end
end


--[[TODO
        * Should "save" a research's progress when it's cancelled until its time limit is reached, then erase it.
        * Maybe each available research's time limit is reduced according to a "challenge factor", which increases for
            each successful research, and decreases for each failed research.
            - Challenge factor function might be like: 0.99^(net successful researches)
            - Maybe failed researches would reduce the challenge factor by how much of the research was completed - so
                failing a nearly completed research would reduce it by almost a full successful research's worth, while queueing
                a research and making zero progress on it would do nothing.
            - Would need to display their current challenge factor
        * Add an alert for when a research's timer is about to expire.
        * Notify player when a research's timer has expired - sound effect, maybe a chat message or alert.
]]
local function research_started_handler(event)
    local force_name = event.research.force.name
    event.research.force.research_progress = 0
    local research_timer = time_limits.time_limits_lookup_table.get_value(event.research.name)*60*60+1
    local finish_tick = event.tick+research_timer
    global.cached_research_time_limits[force_name] = {
        research_name = event.research.name,
        start_tick = event.tick,
        research_timer = research_timer,
        finish_tick = finish_tick,
        handler_id = event_handler.add_timer(finish_tick, handler_name_research_timer_expired, event)
    }
    update_force_GUI(force_name)
end

local function research_finished_handler(event)
    local force_name = event.research.force.name
    local cached_research = global.cached_research_time_limits[force_name]
    if cached_research and cached_research.research_name == event.research.name then
        event_handler.remove_timer(cached_research.finish_tick, cached_research.handler_id)
        global.cached_research_time_limits[force_name] = nil
    end
    update_force_GUI(force_name)
end

local function research_cancelled_handler(event)
    local force_name = event.force.name
    local research_name, _ = next(event.research, nil)
    -- log(serpent.block(event.research))
    local cached_research = global.cached_research_time_limits[force_name]
    if cached_research.research_name == research_name then
        event_handler.remove_timer(cached_research.finish_tick, cached_research.handler_id)
        event.force.set_saved_technology_progress(research_name, 0)
        -- Or should I use force.research_progress = 0?
        global.cached_research_time_limits[force_name] = nil
    end
    update_force_GUI(force_name)
end

local function update_player_GUI(player_index)
    -- log("Player GUI updated for player "..tostring(player_index))
    local force = game.get_player(player_index).force
    if global.cached_research_time_limits[force.name] then
        local GUI_entry = global.research_time_limit_GUIs[player_index]
        local caption = GUI_entry.time_limit_display.caption
        caption[3] = general_util.ticks_to_pretty_time(global.cached_research_time_limits[force.name].finish_tick-game.tick)
        GUI_entry.time_limit_display.caption = caption
        GUI_entry.main_frame.visible = true
    else
        global.research_time_limit_GUIs[player_index].main_frame.visible = false
    end
end

function update_force_GUI(force_name)
    for _, player in pairs(game.forces[force_name].players) do
        update_player_GUI(player.index)
    end
end

local function handler_player_changed_force(event)
    update_player_GUI(event.player_index)
end

local function handler_player_removed(event)
    global.research_time_limit_GUIs[event.player_index].destroy()
    global.research_time_limit_GUIs[event.player_index] = nil
end

local function handler_player_created(event)
    local player = game.get_player(event.player_index)
    local main_frame = player.gui.left.add{type="frame", name="research_challenges_time_limit_time_remaining_display", visible=false}
    main_frame.style.size = {385, 35}
    global.research_time_limit_GUIs[event.player_index] = {
        main_frame = main_frame,
        time_limit_display = main_frame.add{type="label", name="time_remaining_label", caption={"", "Time remaining: ", 0}}
    }
    update_player_GUI(event.player_index)
    log("Player GUI created for player "..tostring(event.player_index))
end

local function handler_on_tick(event)
    for _, player in pairs(game.players) do
        update_player_GUI(player.index)
    end
end

local handler_factories = {}
handler_factories[handler_name_research_timer_expired] = handler_factory_research_timer_expired

local exports = {
    init_handler = init_handler,
    event_handlers = {
        [defines.events.on_research_started] = research_started_handler,
        [defines.events.on_research_cancelled] =  research_cancelled_handler,
        [defines.events.on_research_finished] =  research_finished_handler,
        [defines.events.on_player_created] =  handler_player_created,
        [defines.events.on_player_removed] =  handler_player_removed,
        [defines.events.on_player_changed_force] =  handler_player_changed_force,
        [defines.events.on_tick] =  handler_on_tick
    },
    handler_factories = handler_factories
}

return exports