local function append_to_all_technologies_descriptions(base_string, value_getter)
    local technologies = data.raw["technology"]
    for _, technology in pairs(technologies) do
        local current_description = technology.localised_description
        if not current_description then
            current_description = {"technology-description."..technology.name}
        end
        local value = value_getter(technology.name)
        technology.localised_description = {base_string, value, current_description}
    end
end

local function ticks_to_pretty_time(ticks)
    local UPS = 60
    local pretty_hours = math.floor(ticks/(UPS*60*60))
    local pretty_minutes = math.floor(math.fmod(ticks/(UPS*60), 60))
    local pretty_seconds = math.fmod(ticks/UPS, 60)
    return string.format("%i:%i:%.1f", pretty_hours, pretty_minutes, pretty_seconds)
end

local exports = {
    append_to_all_technologies_descriptions = append_to_all_technologies_descriptions,
    ticks_to_pretty_time = ticks_to_pretty_time
}

return exports