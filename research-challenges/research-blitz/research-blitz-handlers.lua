local event_handler = require("control-event-handler")
local general_util = require("research-challenges-util.general-util")
local research_blitz_time_limits = require("research-blitz-constants")

--[[
    - Notable data structures in global:
        * research_timer_tracker, which is a 2D dictionary indexed first by a force_name, then by a technology_name;
            entries hold information regarding the time limit for that technology to be researched.
        * research_timer_GUIs, which is a dictionary indexed by a player_index; entries hold a reference to the main research
            timer display GUI for the player, as well as a dictionary, timer_entries, holding references to the GUI elements for
            each research timer that is active for the player's force.
    - Other notable information:
        * Research timers are stored per-force, as that is how technologies are stored in the game
        * GUI elements displaying information about a given research's timer are stored per-player, as that is how GUI elements
            are handled in the game
]]

--[[ FIXME
        * Should research dependents and initial researches be stored in global?
        * How to handle if researches change (e.g. mods are added/removed)?
        * What if another mod finishes/reverses a research (e.g. via setting technology.researched)
        * Does this correctly handle a force being removed, especially before a timer expires?
        * GUI:
            - Should have options to sort the research timer display by time remaining, and maybe by fraction of time left
            - Limit to how many researches timers display at a given time.
            - Ability for player to pin researches to the top, or maybe toggle which research timers are visible.
        * Add an alert for when a research timer is about to expire.
        * Notify player when a research's timer has expired - sound effect, maybe an alert or chat message.
]]

--[[TODO/Ideas:
        * Should completing a research give a small bonus to all active timers?
]]

--[[
    Goals:
        -Research timer starts when the research becomes available, either from at least one prerequisite being
            researched, from a force being created and having no prerequisites, or from being enabled after at least one prerequisite
            is researched.
            * Last possibility mostly applies if there are other mods. I should probably start with assuming my mod is the only
                one doing funny stuff with researches.
        -Research timer is cancelled when the research is completed, or if the research is disabled (e.g. if the timer for a
            prerequisite runs out).
        -If the research timer runs out, the research becomes disabled - can't be researched - possibly cancelling current
            research. Additionally, all of its dependents become disabled, too.
    Questions:
        -If a research is disabled, does that automatically disable all its dependents? Does it automatically cancel it
            if it's being researched?
            Answer: Does not auto-cancel it, and does not auto-disable all its dependents - its dependents just become unresearchable.
                    However, if you cancel a queued research, it does cancel all its dependents if they're queued.
]]



-- Declarations

local cancel_research_timer_if_exists -- Might need to remove the "local" in front of the definition?
local create_research_timer_GUI_entry_for_force
local destroy_research_timer_GUI_entry_for_force
local create_research_timer



-- Miscellaneous

local function determine_research_dependents()
    for _, technology in pairs(game.technology_prototypes) do
        global.research_dependents[technology.name] = {}
    end
    for _, technology in pairs(game.technology_prototypes) do
        for _, prerequisite in pairs(technology.prerequisites) do
            table.insert(global.research_dependents[prerequisite.name], technology.name)
        end
    end
end

local function determine_initial_researches()
    for _, technology in pairs(game.technology_prototypes) do
        if not technology.prerequisites or next(technology.prerequisites, nil) == nil then
            log("TECHNOLOGY NAME: "..technology.name)
            table.insert(global.initial_researches, technology.name)
        end
    end
end

local function create_force_time_limit_tracker(force)
    global.research_timer_tracker[force.name] = {}
    for _, technology_name in pairs(global.initial_researches) do
        create_research_timer(game.tick, force.name, technology_name)
    end
end

local function disable_research_and_dependents(force, technology_name)
    force.technologies[technology_name].enabled = false
    if force.current_research and force.current_research.name == technology_name then
        log("Cancelling research "..technology_name.." for force "..force.name..".")
        force.cancel_current_research()
    end
    cancel_research_timer_if_exists(force.name, technology_name)
    for _, dependent_technology_name in pairs(global.research_dependents[technology_name]) do
        disable_research_and_dependents(force, dependent_technology_name)
    end
end



-- Timer management

local handler_name_research_time_limit_expired = "research_time_limit_expired"
local function handler_factory_research_time_limit_expired(args)
    return function(nth_tick_event)
        local force = game.forces[args.force_name]
        if force.valid then
            local technology = force.technologies[args.technology_name]
            if technology.valid and not technology.researched then
                disable_research_and_dependents(force, technology.name)
            end
        end
    end
end

function create_research_timer(current_tick, force_name, technology_name)
    if type(technology_name) ~= "string" then
        error("Received a non-string technology name: "..serpent.block(technology_name).."; technology.name="..technology_name.name)
    end
    local timer_duration = research_blitz_time_limits.time_limit_lookup_table.get_value(technology_name)*(60*60)+1
    local final_tick = current_tick+timer_duration
    -- local x = global.research_timer_tracker[force_name][technology_name]
    log(serpent.block("Creating timer for technology "..technology_name.." for force "..force_name.."."))
    global.research_timer_tracker[force_name][technology_name] = {
        start_tick = current_tick,
        timer_duration = timer_duration,
        final_tick = final_tick,
        timer_id = event_handler.add_timer(final_tick, handler_name_research_time_limit_expired, {
            force_name = force_name,
            technology_name = technology_name
        })
    }
    create_research_timer_GUI_entry_for_force(force_name, technology_name)
end

function cancel_research_timer_if_exists(force_name, technology_name)
    local timer_entry = global.research_timer_tracker[force_name][technology_name]
    if timer_entry then
        event_handler.remove_timer(timer_entry.final_tick, timer_entry.timer_id)
        global.research_timer_tracker[force_name][technology_name] = nil
        destroy_research_timer_GUI_entry_for_force(force_name, technology_name)
    end
end



-- GUI management

local function update_research_timer_GUI_entry(player_index, technology_name)
    local player_research_timer_GUI_entry = global.research_timer_GUIs[player_index].timer_entries[technology_name]
    local force_research_timer_entry = global.research_timer_tracker[game.get_player(player_index).force.name][technology_name]
    local caption = player_research_timer_GUI_entry.text_display.caption
    caption[4] = general_util.ticks_to_pretty_time(force_research_timer_entry.final_tick-game.tick)
    player_research_timer_GUI_entry.text_display.caption = caption
    -- player_research_timer_GUI_entry.text_display.caption[4] = force_research_timer_entry.final_tick-game.tick
    player_research_timer_GUI_entry.progress_bar.value = (game.tick-force_research_timer_entry.start_tick)/force_research_timer_entry.timer_duration
end

--[[Preconditions:
        * Research timer for the specified technology and player's force already exists.
        * GUI setup for the player already exists
]]
local function create_research_timer_GUI_entry(player_index, technology_name)
    log(serpent.block(technology_name))
    local player_research_timer_GUI_info = global.research_timer_GUIs[player_index]
    local force_research_timer_entry = global.research_timer_tracker[game.get_player(player_index).force.name]
    local entry_frame = player_research_timer_GUI_info.main_frame.add{type="frame", name="timer_frame_"..technology_name, direction="vertical"}
    local timer_text = entry_frame.add{type="label", name="timer_text_"..technology_name, caption={"", {"technology-name."..technology_name}, ": ", 0}}
    local progress_bar = entry_frame.add{type="progressbar", name="timer_progress_bar_"..technology_name, value=0.0}
    player_research_timer_GUI_info.timer_entries[technology_name] = {entry_frame=entry_frame, text_display=timer_text, progress_bar=progress_bar}
    update_research_timer_GUI_entry(player_index, technology_name)
end

local function destroy_research_timer_GUI_entry(player_index, technology_name)
    global.research_timer_GUIs[player_index].timer_entries[technology_name].entry_frame.destroy()
    global.research_timer_GUIs[player_index].timer_entries[technology_name] = nil
end

local function update_research_timer_GUI(player_index)
    for technology_name, _ in pairs(global.research_timer_GUIs[player_index].timer_entries) do
        update_research_timer_GUI_entry(player_index, technology_name)
    end
end

function create_research_timer_GUI_entry_for_force(force_name, technology_name)
    for _, player in pairs(game.forces[force_name].players) do
        create_research_timer_GUI_entry(player.index, technology_name)
    end
end

function destroy_research_timer_GUI_entry_for_force(force_name, technology_name)
    for _, player in pairs(game.forces[force_name].players) do
        destroy_research_timer_GUI_entry(player.index, technology_name)
    end
end

local function create_research_timer_GUI_entries_for_player(player_index)
    log(serpent.block(global.research_timer_tracker[game.get_player(player_index).force.name]))
    for technology_name, _ in pairs(global.research_timer_tracker[game.get_player(player_index).force.name]) do
        create_research_timer_GUI_entry(player_index, technology_name)
    end
end

local function destroy_research_timer_GUI_entries_for_player(player_index)
    for technology_name, _ in pairs(global.research_timer_GUIs[player_index].timer_entries) do
        destroy_research_timer_GUI_entry(player_index, technology_name)
    end
    global.research_timer_GUIs[player_index].timer_entries = {}
end



-- Handlers

local function handler_research_finished(event)
    local force_name = event.research.force.name
    -- Remove timer for this research (assume they finished the research before the timer expired)
    cancel_research_timer_if_exists(force_name, event.research.name)
    -- Identify any researches which this was a prerequisite of; if their timers aren't already ticking, start them.
    for _, dependent_name in pairs(global.research_dependents[event.research.name]) do
        if not global.research_timer_tracker[force_name][dependent_name] then
            create_research_timer(event.tick, force_name, dependent_name)
        end
    end
    -- for _, dependent_name in pairs(global.research_dependents[event.research_name]) do
    --     local prerequisites_unsatisfied = false
    --     for _, prerequisite in pairs(event.research.force.technologies[dependent_name].prerequisites) do
    --         if not prerequisite.researched then
    --             prerequisites_unsatisfied = true
    --         end
    --     end
    --     if not prerequisites_unsatisfied then
    --         create_research_timer(event.tick, force_name, dependent_name)
    --     end
    -- end
end

local function handler_force_created(event)
    create_force_time_limit_tracker(event.force)
end

local function handler_player_created(event)
    local player = game.get_player(event.player_index)
    local screen_left = player.gui.left
    local main_frame = screen_left.add{type="frame", name="research_challenges_research_blitz_timer_display", caption="Time Remaining:", direction="vertical"}
    main_frame.style.width = 270
    global.research_timer_GUIs[event.player_index] = {
        main_frame = main_frame,
        -- content_frame = main_frame.add{type="frame", name="content_frame", direction="vertical"},
        timer_entries = {}
    }
    create_research_timer_GUI_entries_for_player(event.player_index)
end

local function handler_player_removed(event)
    global.research_timer_GUIs[event.player_index].main_frame.destroy()
    global.research_timer_GUIs[event.player_index] = nil
end

local function handler_player_changed_force(event)
    destroy_research_timer_GUI_entries_for_player(event.player_index)
    create_research_timer_GUI_entries_for_player(event.player_index)
end

local function handler_on_tick(event)
    for _, player in pairs(game.players) do
        update_research_timer_GUI(player.index)
    end
end

local function handler_init(event)
    global.research_timer_tracker = {}
    global.research_timer_GUIs = {}
    global.research_dependents = {}
    global.initial_researches = {}
    determine_initial_researches()
    determine_research_dependents()
    for _, force in pairs(game.forces) do
        create_force_time_limit_tracker(force)
    end
end



local exports = {
    init_handler = handler_init,
    event_handlers = {
        [defines.events.on_tick] = handler_on_tick,
        [defines.events.on_research_finished] = handler_research_finished,
        [defines.events.on_force_created] = handler_force_created,
        [defines.events.on_player_created] = handler_player_created,
        [defines.events.on_player_removed] = handler_player_removed,
        [defines.events.on_player_changed_force] = handler_player_changed_force
    },
    handler_factories = {
        [handler_name_research_time_limit_expired] = handler_factory_research_time_limit_expired
    }
}

return exports