local alternate_constants = require("alternates-constants")

-- FIXME Can queue more than one alternate of a set.

local function get_technology_set_information(technology)
    if technology.localised_name and technology.localised_name[1] == "?" and technology.localised_name[2] == "DUMMY" then
        log("Found what looks like a set information dummy technology: "..technology.name)
        local success, result = serpent.load(table.concat(technology.localised_name[3]))
        if success then
            return result
        end
        log("Encountered technology that looks like a set information dummy technology, but it had an invalid serialized set information string. Technology: "..technology.name.."; invalid set informations string: "..technology.localised_name[3])
        -- local raw_technology_set_info = technology.localised_name[3]
        -- if type(raw_technology_set_info) == "table" then
        --     if raw_technology_set_info[1] == alternate_constants.technology_set_code then
        --         local is_core = raw_technology_set_info[3] == alternate_constants.core_technology_code
        --         if not is_core and raw_technology_set_info[3] ~= alternate_constants.alternate_technology_code then
        --             error("Found technology with defined, but invalid, technology set information tag. Technlogy name: "..technology.name)
        --         end
        --         if not is_core and tonumber(raw_technology_set_info[4]) == nil then
        --             error("Found alternate technology with a missing or invalid ID. Technology name: "..technology.name.."; Technology set info: "..serpent.block(raw_technology_set_info))
        --         end
        --         return {
        --             set_name = raw_technology_set_info[2],
        --             is_core = is_core,
        --             alternate_id = tonumber(raw_technology_set_info[4])
        --         }
        --     end
        -- end
    end
    return nil
end

local function disable_and_cancel(technology)
    technology.enabled = false
    if technology.force.current_research and technology.force.current_research.name == technology.name then
        technology.force.cancel_current_research()
    else
        if technology.force.research_queue_enabled then
            local index, queued_technology = next(technology.force.research_queue, nil)
            while index do
                if queued_technology.name == technology.name then
                    technology.force.research_queue[index] = nil
                    technology.force.research_queue = technology.force.research_queue
                    break
                end
                index, queued_technology = next(technology.force.research_queue, index)
            end
        end
    end
end

local function handler_research_finished(event)
    local technology_set_info = global.technology_set_lookup[event.research.name]
    if technology_set_info and technology_set_info.core ~= event.research.name then
        -- Disable other alternates, complete core research
        local force = event.research.force
        force.technologies[technology_set_info.core].researched = true
        log("Hello")
        for _, alternate_name in pairs(technology_set_info.alternates) do
            if alternate_name ~= event.research.name then
                -- force.technologies[alternate_name].enabled = false
                log(alternate_name..".researched="..tostring(force.technologies[alternate_name].enabled))
                disable_and_cancel(force.technologies[alternate_name])
            else
                log("Found this research: "..event.research.name.."; enabled="..tostring(event.research.enabled))
            end
        end

        -- Initial research handling
        if technology_set_info.initial and event.research.name ~= technology_set_info.core then
            global.force_initial_research_tracker[force.name] = global.force_initial_research_tracker[force.name] - 1
            log("n_initial_researches="..tostring(global.n_initial_researches))
            if global.force_initial_research_tracker[force.name] <= 0 then
                for _, technology_set_info in pairs(global.technology_sets) do
                    if technology_set_info.initial then
                        force.technologies[technology_set_info.core].enabled = false
                        force.technologies[technology_set_info.core].visible_when_disabled = false
                        force.technologies[technology_set_info.core].researched = false
                    end
                end
                for _, technology in pairs(force.technologies) do
                    local technology_set_info = global.technology_set_lookup[technology.name]
                    if not (technology_set_info and technology_set_info.initial) then
                        if technology_set_info then
                            if technology.name == technology_set_info.core then
                                technology.visible_when_disabled = true
                            else
                                if technology.name ~= technology_set_info.set_info_dummy_technology then
                                    technology.enabled = true
                                end
                            end
                        else
                            technology.enabled = true
                        end
                    end
                end
            end
        end
    end
end

local function set_up_force_researches(force)
    for _, technology in pairs(force.technologies) do
        -- Hide all non-initial technologies
        if not (global.technology_set_lookup[technology.name] and global.technology_set_lookup[technology.name].initial) then
            technology.enabled = false
            technology.visible_when_disabled = false
        end
    end
    global.utility_surface.create_entity{name=alternate_constants.initial_technology_lab_name, position={x=0, y=0}, force=force}
    log("n_initial_researches="..tostring(global.n_initial_researches))
    global.force_initial_research_tracker[force.name] = global.n_initial_researches
end

local function handler_force_created(event)
    set_up_force_researches(event.force)
end

local function handler_init(event)
    global.technology_sets = {}
    global.technology_set_lookup = {}
    global.force_initial_research_tracker = {}
    local n_initial_researches = 0
    for _, technology in pairs(game.technology_prototypes) do
        log("Processing technology "..technology.name.."; order="..technology.order)
        local technology_set_info = get_technology_set_information(technology)
        -- TODO Validate that all sets have a core.
        if technology_set_info then
            log("Found set information technology: "..technology.name)
            if global.technology_sets[technology_set_info.set_name] then
                error("Encountered two technology set tables for the same set_name. Set table one: "..serpent.block(global.technology_sets[technology_set_info.set_name]).."; Set table two: "..serpent.block(technology_set_info))
            end
            global.technology_sets[technology_set_info.set_name] = technology_set_info
            global.technology_set_lookup[technology.name] = technology_set_info
            global.technology_set_lookup[technology_set_info.core] = technology_set_info
            for _, alternate_technology_name in pairs(technology_set_info.alternates) do
                global.technology_set_lookup[alternate_technology_name] = technology_set_info
            end
            if technology_set_info.initial then
                n_initial_researches = n_initial_researches+1
            end
            -- if not global.technology_sets[technology_set_info.set_name] then
            --     global.technology_sets[technology_set_info.set_name] = {
            --         alternates = {}
            --     }
            -- end
            -- if technology_set_info.is_core then
            --     log("Core technology found: "..technology.name)
            --     if global.technology_sets[technology_set_info.set_name].core then
            --         error("Technology set has two core technologies."..global.technology_sets[technology_set_info.set_name].core.."; Technology 2 name: "..technology.name)
            --     end
            --     global.technology_sets[technology_set_info.set_name].core = technology
            -- else
            --     log("Alternate technology found: "..technology.name)
            --     log("Set name: "..technology_set_info.set_name)
            --     if global.technology_sets[technology_set_info.set_name].alternates[technology_set_info.alternate_id] then
            --         error("Found two alternate technologies with the same set name and ID. Technology name: "..technology.name)
            --     end
            --     global.technology_sets[technology_set_info.set_name].alternates[technology_set_info.alternate_id] = technology
            -- end
            -- global.technology_set_lookup[technology.name] = technology_set_info
        end
    end
    global.n_initial_researches = n_initial_researches

    global.utility_surface = game.create_surface("alternates-utility")
    for _, force in pairs(game.forces) do
        set_up_force_researches(force)
    end
end

local exports = {
    init_handler = handler_init,
    event_handlers = {
        [defines.events.on_research_finished] = handler_research_finished,
        [defines.events.on_force_created] = handler_force_created
    }
}

return exports