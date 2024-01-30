local fractions = require("minimum-throughput-constants")

local ticks_between_research_checks = 60
--[[TODO
    * Should maybe dynamically adjust how quickly it checks a force's research progress based on how quickly they are
        progressing.
    * Notify player when they are losing research progress due to insufficient throughput - maybe a sound effect, an alert,
        and/or a chat message. Is there a way to make the minimum throughput GUI flash, like how the technology GUI element
        in the top-right of the screen flashes if a research is finished and there aren't any more researches queued? (And
        maybe briefly when any research is completed?)
    * How to handle a research being cancelled?
]]

-- FIXME Does this correctly handle it if a force is removed?

local function adjust_research_progress(event)
    for _, force in pairs(game.forces) do
        local current_research = force.current_research
        if current_research then
            -- If the force's current research doesn't match the cached research, update the cached research
            if not global.current_researches[force.name] or current_research.name ~= global.current_researches[force.name].technology_name then
                global.current_researches[force.name] = {
                    technology_name = current_research.name,
                    minimum_throughput_fraction = fractions.minimum_throughput_fractions_table.get_value(current_research.name)
                }
                log("Updated cached research data for force \""..force.name
                    .."\". New research is \""..global.current_researches[force.name].technology_name
                    .."\" with minimum throughput fraction "..tostring(global.current_researches[force.name].minimum_throughput_fraction))
            end
            -- Update the force's research progress based on their current research's minimum throughput.
            local new_research_progress = force.research_progress - global.current_researches[force.name].minimum_throughput_fraction/ticks_between_research_checks
            force.research_progress = math.max(0, new_research_progress)
            -- TODO Have an option for the player's research to be cancelled if they do not satisfy the minimum throughput
        else
            global.current_researches[force.name] = nil
        end
    end
end

local function clean_old_forces(event)
    local old_forces = {}
    for force_name, _ in pairs(global.current_researches) do
        if not (game.forces[force_name] and game.forces[force_name].valid) then
            table.insert(old_forces, force_name)
        end
    end
    for _, force_name in pairs(old_forces) do
        log("Removed deleted force: "..force_name)
        global.current_researches[force_name] = nil
    end
end

local function set_player_GUI_minimum_throughput(player_index)
    local player_GUI_entry = global.minimum_throughput_GUIs[player_index]
    local force = game.players[player_index].force
    if global.current_researches[force.name] then
        local current_research_entry = global.current_researches[force.name]
        local technology = force.technologies[current_research_entry.technology_name]
        local ingredient_names = {""}
        for _, ingredient in pairs(technology.research_unit_ingredients) do
            table.insert(ingredient_names, "[item="..ingredient.name.."]")
        end
        local effective_throughput = global.current_researches[force.name].minimum_throughput_fraction*technology.research_unit_count
        local new_caption_entry = {"", ingredient_names, "x ", effective_throughput, " per minute."}
        -- Don't know how to get the game to update a text caption without writing to the caption member.
        local caption = player_GUI_entry.throughput_display.caption
        caption[4] = new_caption_entry
        player_GUI_entry.throughput_display.caption = caption
        -- player_GUI_entry.throughput_display.caption[4] = new_caption_entry
        -- player_GUI_entry.throughput_display.caption = player_GUI_entry.throughput_display.caption
        player_GUI_entry.main_frame.visible = true
    else
        player_GUI_entry.main_frame.visible = false
    end
end

local function set_force_players_GUI_minimum_throughput(force_name)
    for _, player in pairs(game.forces[force_name].players) do
        set_player_GUI_minimum_throughput(player.index)
    end
end

local function handler_research_started(event)
    log("Research started for force: "..event.research.force.name)
    global.current_researches[event.research.force.name] = {
        technology_name=event.research.name,
        minimum_throughput_fraction=fractions.minimum_throughput_fractions_table.get_value(event.research.name)
    }
    set_force_players_GUI_minimum_throughput(event.research.force.name)
end

local function handler_research_cancelled(event)
    log("Research cancelled for force: "..event.force.name)
    global.current_researches[event.force.name] = nil
    set_force_players_GUI_minimum_throughput(event.force.name)
end

local function handler_research_finished(event)
    log("Research finished for force: "..event.research.force.name)
    global.current_researches[event.research.force.name] = nil
    set_force_players_GUI_minimum_throughput(event.research.force.name)
end

local function handler_player_changed_force(event)
    set_player_GUI_minimum_throughput(event.player_index)
end

local function handler_player_created(event)
    -- FIXME Would like to also display the current research right above the minimum throughput, so player doens't have to look
    --  in two different places.
    local player = game.get_player(event.player_index)
    local screen_left = player.gui.left
    local main_frame = screen_left.add{type="frame", name="research_challenges_minimum_throughput_throughput_display", visible=false}
    main_frame.style.size = {385, 35}
    global.minimum_throughput_GUIs[event.player_index] = {
        main_frame = main_frame,
        throughput_display = main_frame.add{type="label", name="minimum_throughput_label", caption={"", {"research-challenges.minimum-throughput-GUI-text"}, ": ", 0}}
    }
    set_player_GUI_minimum_throughput(event.player_index)
end

local function handler_player_removed(event)
    global.minimum_throughput_GUIs[event.player_index].main_frame.destroy()
    global.minimum_throughput_GUIs[event.player_index] = nil
end

local function handler_init(event)
    global.current_researches = {}
    global.minimum_throughput_GUIs = {}
    for _, technology in pairs(game.forces["player"].technologies) do
        log(technology.name..": "..tostring(technology.enabled))
    end
end

-- event_handler.add_nth_tick_handler(ticks_between_research_checks, adjust_research_progress)
-- event_handler.add_nth_tick_handler(ticks_between_research_checks*10, clean_old_forces)

-- script.on_nth_tick(ticks_between_research_checks, adjust_research_progress)

-- script.on_nth_tick(ticks_between_research_checks*10, clean_old_forces)

local exports = {
    init_handler = handler_init,
    event_handlers = {
        [defines.events.on_player_created] = handler_player_created,
        [defines.events.on_player_removed] = handler_player_removed,
        [defines.events.on_player_changed_force] = handler_player_changed_force,
        [defines.events.on_research_started] = handler_research_started,
        [defines.events.on_research_finished] = handler_research_finished,
        [defines.events.on_research_cancelled] = handler_research_cancelled
    },
    non_conditional_nth_tick_handlers = {
        {nth_tick=ticks_between_research_checks, handler=adjust_research_progress},
        {nth_tick=ticks_between_research_checks*10, handler=clean_old_forces},
    }
}

return exports