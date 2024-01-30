local alternate_constants = require("alternates-constants")

local DEBUG = true

--[[Things to account for:
    Relative value of items - some items are only crafted a few times, others are crafted many times. Also, some items change in
        value over the course of a game - you initially need far less copper than iron, but this changes in the later game.
    Maybe also account for the "crafting tier" of an item - how many crafting steps it takes to craft it from raw resources.
        Not to mention the raw cost of a given item.
    And, how long a research unit takes matters less and less the further into the game you get.
    How much you get from a given recipe dramatically changes how "good" it is - maybe should calculate that first, then the ingredients
    Some way to round large numbers to the nearest multiple of 5/10/20/50/100/etc., rounding away from the initial value?
    If an item amount is 1, maybe instead use a random chance of doubling/tripling it.
    Recipe duration might mostly be impactful for high-demand items, like circuits.
    Maybe scale science costs more dramatically.
    Also, for single-input/output recipes - effect of multiplying input or output kinda multiplies the whole recipe's "goodness"
        To have a tradeoff, you need something that you're trading off against.
    Possible bits of "long-distance logic":
    * Trade off a cheaper/better machine against cheaper/more efficient recipes in that machine.
    Barreling recipes and other symmetric recipes - should mirror each other.
]]

--[[TODO/Ideas
        * Maybe use a points-based system for modifying alternates, where each research is assigned some number of modification
            points, and an equal number of positive and negative modifications are distributed - so one research might have a
            recipe's cost reduced by three positive modification points, its research cost increased by two negative modification
            points, and its research time/unit increased by one negative modification point.
        * Maybe better recipes can be counter-balanced by general negative modifiers, like a 50% increase in electricity consumed.
            - Or perhaps these modifiers (positive and negative) could be what differs between the alternatives.
        * Perhaps have "tiers" of recipe/technology modifications, where tier 1 might apply a 20% increase or 50+ unit increase
            in a technology's cost (whichever is greater), tier 2 would be a 40% increase or 100+ unit increase in a technology's
            cost (whichever is greater), and so on.
]]

--[[
    What would a good tradeoff for "automation" (typical first research) look like?
        * More expensive assembling machine for cheaper science packs - generally worthwhile unless it's like 100x more expensive.
            - Maybe a 2/5
        * Pricier, but more compact assembling machine
            - 4/5?
        * Pricier assembling machine, but long-handed inserters are cheaper.
            - 4/5
        * Assembling machine has better stats, but its crafting recipe is more expensive and takes longer (50x or more), and the
            machine consumes more electricity
]]

--[[Creating machine variants:
        Parameters (for crafting type machines):
            - Size (width, height; limited to certain amount of stretch)
            - Power usage (power)
            - Built in productivity bonus
            - Speed
            - Fluid stuff
                + Can handle fluids
                + Location of fluidboxes
            - Effect stuff
                + Number of module slots
                + Supported effects
                + Effect "efficiency" - beacons that affect the machine
            - Energy type
            - Can be picked up after placing
        Process:
            - Identify and extract machine prototype
            - Redirect corresponding recipe to point to it.
            - Modify machine stats appropriately
]]

local item_prototype_categories = {
    "item",
    "ammo",
    "capsule",
    "gun",
    "item-with-entity-data",
    "item-with-label",
    "item-with-inventory",
    "blueprint-book",
    "item-with-tags",
    "selection-tool",
    "blueprint",
    "copy-paste-tool",
    "deconstruction-item",
    "upgrade-item",
    "module",
    "rail-planner",
    "spidertron-remote",
    "tool",
    "armor",
    "mining-tool",
    "repair-tool"
}

local function normalize_ingredient_in_place(ingredient)
    if not ingredient.name then
        local name = ingredient[1]
        local amount = ingredient[2]
        ingredient[2] = nil
        ingredient[1] = nil
        ingredient.name = name
        ingredient.amount = amount
        ingredient.type = "item"
    end
end

local function normalize_result_in_place(result)
    if not result.name then
        local name = result[1]
        local amount = result[2]
        result[2] = nil
        result[1] = nil
        result.name = name
        result.amount = amount
        result.type = "item"
    end
end

local function ensure_order_exists(prototype)
    if not prototype.order then
        prototype.order = string.sub(prototype.name, 1, 190)
    end
end

local function create_recipe_unlock(recipe_name)
    return {
        type = "unlock-recipe",
        recipe = recipe_name
    }
end

local function fragment_string(str)
    local fragments = {}
    for i = 1, string.len(str), 200 do
        table.insert(fragments, string.sub(str, i, i+200-1))
    end
    return fragments
end

local function calculate_n_pairs(table)
    local n = 0
    for _, _ in pairs(table) do
        n = n + 1
    end
    return n
end

-- Generate a random number in the intersection of the ranges [-absolute_max_value, absolute_max_value) and [center_point-1.5, center_point+1.5), with
--  center_point clamped to the range [-absolute_max_value, absolute_max_value]
-- Default values: absolute_max_value = 2.0
local function random_float_around_center_point(center_point, absolute_max_value)
    absolute_max_value = absolute_max_value or 2.0
    local normal_max_deviation = 1.5
    local clamped_center_point = math.max(-absolute_max_value, math.min(absolute_max_value, center_point))
    local minimum_value = math.max(-absolute_max_value, clamped_center_point-normal_max_deviation)
    local maximum_value = math.min(absolute_max_value, clamped_center_point+normal_max_deviation)
    local random_range = maximum_value-minimum_value
    local value = math.random()*random_range+minimum_value
    return value
end

local function round(value, place)
    local place = place or 0
    local factor = 10^place
    return math.floor(value*factor+0.5)/factor
end

local function clamp(value, minimum, maximum)
    return math.min(maximum, math.max(minimum, value))
end

local function find_item_prototype(item_name)
    for _, category in pairs(item_prototype_categories) do
        if data.raw[category][item_name] then
            return {category=category, prototype=data.raw[category][item_name]}
        end
    end
    error("Couldn't find item: "..item_name)
end

local function is_item_stackable(item_name)
    -- log(item_name)
    local item_prototype_result = find_item_prototype(item_name)
    -- if item_name == "power-armor" then
    --     log(serpent.block(item_prototype_result))
    --     log(serpent.block(item_prototype_result.prototype.flags))
    -- end
    if item_prototype_result.category == "armor" then -- TODO Can armo stack?
        return false
    end
    if item_prototype_result.prototype.stack_size == 1 then
        return false
    end
    if not item_prototype_result.prototype.flags then
        return true
    end
    for _, flag in pairs(item_prototype_result.prototype.flags) do
        if flag == "not-stackable" then
            return false
        end
    end
    return true
end

local function has_levels(technology)
    -- log(technology.name.."$"..string.sub(technology.name, string.len(technology.name), string.len(technology.name)))
    -- log()
    if technology.max_level then
        return true
    end
    if tonumber(string.sub(technology.name, string.len(technology.name), string.len(technology.name))) then
        return true
    end
    
    return false
end

local function modify_alternate_recipe(alternate_recipe, initial_net_change)
    local net_change = initial_net_change
    -- if not alternate_recipe.localised_name then
    --     alternate_recipe.localised_name = {"recipe-name."..alternate_recipe.name}
    -- end
    -- if not alternate_recipe.localised_description then
    --     alternate_recipe.localised_description = {"recipe-description."..alternate_recipe.name}
    -- end
    -- alternate_recipe.localised_name = {"", alternate_recipe.localised_name, " ", {"research-challenges.alternate", i}}
    for _, ingredient in pairs(alternate_recipe.ingredients) do
        if not ingredient.catalyst_amount then -- TODO Special handling for catalyst computation
            if ingredient.type == "fluid" then
                -- Compute a random power, because it's assumed that doubling the amount of an ingredient is as
                -- bad as halving the amount is good.
                local power = random_float_around_center_point(net_change)
                local raw_amount = (2^power)*ingredient.amount
                -- Ensure fluid amount is rounded to the tenths place, and no less than 0.1
                local corrected_amount = math.max(0.1, round(raw_amount, 1))
                local effective_power = math.log(corrected_amount/ingredient.amount, 2)
                ingredient.amount = corrected_amount
                -- A negative factor on an ingredient is a positive change.
                net_change = net_change - effective_power/4
            else -- Item ingredient
                -- FIXME Can non-stackable ingredients have amounts other than one?
                normalize_ingredient_in_place(ingredient)
                local initial_amount = ingredient.amount
                local power = random_float_around_center_point(net_change)
                local raw_amount = (2^power)*initial_amount
                local corrected_amount = math.max(1, round(raw_amount))
                local effective_power = math.log(corrected_amount/initial_amount, 2)
                ingredient.amount = corrected_amount
                net_change = net_change - effective_power/4
            end
        end
    end
    if not alternate_recipe.energy_required then
        alternate_recipe.energy_required = 0.5 -- Vanilla default
    end
    local time_power = random_float_around_center_point(net_change)
    local raw_time = (2^time_power)*alternate_recipe.energy_required
    local corrected_time = math.max(0.1, round(raw_time, 1))
    local effective_time_power = math.log(corrected_time/alternate_recipe.energy_required, 2)
    alternate_recipe.energy_required = corrected_time
    net_change = net_change - effective_time_power/2
    if not alternate_recipe.results then -- TODO Special handling for list of results
        if is_item_stackable(alternate_recipe.result) then
            if not alternate_recipe.result_count then
                alternate_recipe.result_count = 1
            end
            local result_power = random_float_around_center_point(-net_change)
            local raw_count = (2^result_power)*alternate_recipe.result_count
            local corrected_count = math.max(1, round(raw_count))
            local effective_result_power = math.log(corrected_count/alternate_recipe.result_count, 2)
            alternate_recipe.result_count = corrected_count
            net_change = net_change + effective_result_power
        end
    end
    return net_change
end

local function modify_technology_alternate_initial(alternate_technology, suffix)
    -- Vary effects
    local net_change = 0 -- How "good" a given alternate is compared to the baseline
    if alternate_technology.effects then
        for _, effect in pairs(alternate_technology.effects) do
            if effect.type == "unlock-recipe" then
                -- TODO Special handling for recipes unlocked by multiple technologies
                local alternate_recipe = table.deepcopy(data.raw["recipe"][effect.recipe])
                local alternate_recipe_name = alternate_recipe.name..suffix
                alternate_recipe.name = alternate_recipe_name
                effect.recipe = alternate_recipe_name
                if not alternate_recipe.order then
                    alternate_recipe.order = string.sub(alternate_recipe.name, 1, 190)
                end
                alternate_recipe.order = string.sub(alternate_recipe.order, 1, 190)..suffix
                if alternate_recipe.normal or alternate_recipe.expensive then
                    local normal_net_change = net_change
                    if alternate_recipe.normal then
                        normal_net_change = modify_alternate_recipe(alternate_recipe.normal, net_change)
                    end
                    local expensive_net_change = net_change
                    if alternate_recipe.expensive then
                        expensive_net_change = modify_alternate_recipe(alternate_recipe.expensive, net_change)
                    end
                    net_change = (normal_net_change+expensive_net_change)/2
                else
                    net_change = modify_alternate_recipe(alternate_recipe, net_change)
                end
                log("Final net_change: "..tostring(net_change))
                data:extend{alternate_recipe}
            end
        end
    end
    
    if not (alternate_technology.normal or alternate_technology.expensive) then -- TODO Special handling for normal/expensive modes
        if not alternate_technology.unit.count_formula then -- TODO Special handling for formula-based research costs
            local count_power = random_float_around_center_point(net_change)
            local raw_count = (2^count_power)*alternate_technology.unit.count
            local corrected_count = math.max(1, round(raw_count))
            local effective_count_power = math.log(corrected_count/alternate_technology.unit.count, 2)
            alternate_technology.unit.count = corrected_count
            net_change = net_change - effective_count_power/2

            local time_power = random_float_around_center_point(net_change)
            local raw_time = (2^time_power)*alternate_technology.unit.time
            local corrected_time = math.max(0.1, round(raw_time, 1))
            local effective_time_power = math.log(corrected_time/alternate_technology.unit.time, 2)
            alternate_technology.unit.time = corrected_time
            net_change = net_change - effective_time_power/4
        end
    end
end

local function create_weight(positive, negative)
    return {
        positive=positive,
        negative=negative
    }
end

local function determine_allocation_indices(allocation_targets, unshareable_targets)
    -- Allocate points
    local function compute_nested_random(max_value)
        local result = 2
        for i = 1, 3, 1 do
            if result == max_value then
                break
            end
            -- if true then
            --     log("Empty interval: "..tostring(result)..":"..tostring(max_value))
            -- end
            result = math.random(result, max_value)
        end
        return result
    end
    -- log(serpent.block(allocation_targets))
    local n_positive = compute_nested_random(calculate_n_pairs(allocation_targets))
    local n_negative = compute_nested_random(calculate_n_pairs(allocation_targets))
    local function generate_raw_allocation_indices(n_indices)
        local allocation_indices = {}
        for index, _ in pairs(allocation_targets) do
            table.insert(allocation_indices, index)
        end
        -- for i = 1, calculate_n_pairs(allocation_targets), 1 do
        --     table.insert(allocation_indices, i)
        -- end
        for i = 1, ((calculate_n_pairs(allocation_targets))-n_indices) do
            table.remove(allocation_indices, math.random(calculate_n_pairs(allocation_indices)))
        end
        return allocation_indices
    end
    local raw_positive_allocation_indices = generate_raw_allocation_indices(n_positive)
    local raw_negative_allocation_indices = generate_raw_allocation_indices(n_negative)
    local positive_allocation_indices = {}
    local negative_allocation_indices = {}
    local shared_allocation_indices = {}
    local at_least_one_positive_index = false
    local at_least_one_negative_index = false
    for _, positive_index in pairs(raw_positive_allocation_indices) do
        local shared = false
        for _, negative_index in pairs(raw_negative_allocation_indices) do
            if positive_index == negative_index and unshareable_targets[positive_index] then
                shared = true
                break
            end
        end
        if not shared then
            at_least_one_positive_index = true
            table.insert(positive_allocation_indices, positive_index)
        else
            table.insert(shared_allocation_indices, positive_index)
        end
    end
    for _, negative_index in pairs(raw_negative_allocation_indices) do
        local shared = false
        for _, shared_index in pairs(shared_allocation_indices) do
            if negative_index == shared_index then
                shared = true
                break
            end
        end
        if not shared then
            at_least_one_negative_index = true
            table.insert(negative_allocation_indices, negative_index)
        end
    end
    for _, shared_index in pairs(shared_allocation_indices) do
        if at_least_one_negative_index == at_least_one_positive_index then
            if math.random(2) == 2 then
                table.insert(positive_allocation_indices, shared_index)
                at_least_one_positive_index = true
            else
                table.insert(negative_allocation_indices, shared_index)
                at_least_one_negative_index = true
            end
        else -- Ensure both positive and negatives get at least one.
            if not at_least_one_positive_index then
                table.insert(positive_allocation_indices, shared_index)
                at_least_one_positive_index = true
            else
                table.insert(negative_allocation_indices, shared_index)
                at_least_one_negative_index = true
            end
        end
    end

    if DEBUG then
        local function validate_allocation_indices(allocation_indices)
            local already_encountered = {}
            for _, index in pairs(allocation_indices) do
                if already_encountered[index] then
                    error("Encountered duplicate index in allocation index array. Array: "..serpent.dump(allocation_indices))
                end
                already_encountered[index] = true
            end
        end
        validate_allocation_indices(positive_allocation_indices)
        validate_allocation_indices(negative_allocation_indices)
    end
    return positive_allocation_indices, negative_allocation_indices
end

local function allocate_points(allocation_targets, positive_allocation_indices, negative_allocation_indices, positive_points, negative_points)
    local n_positive_allocation_indices = calculate_n_pairs(positive_allocation_indices)
    local n_negative_allocation_indices = calculate_n_pairs(negative_allocation_indices)
    if n_positive_allocation_indices then
        while positive_points > 0 do
            local positive_index = positive_allocation_indices[math.random(n_positive_allocation_indices)]
            local positive_weight = allocation_targets[positive_index].weight.positive
            allocation_targets[positive_index].positive = allocation_targets[positive_index].positive + positive_weight
            positive_points = positive_points - positive_weight
        end
        -- for i = 1, positive_points, 1 do
        --     local positive_index = positive_allocation_indices[math.random(n_positive_allocation_indices)]
        --     allocation_targets[positive_index].positive = allocation_targets[positive_index].positive + 1
        -- end
    else
        log("[WARN] Zero positive allocation indices selected.")
    end
    if n_negative_allocation_indices then
        while negative_points > 0 do
            local negative_index = negative_allocation_indices[math.random(n_negative_allocation_indices)]
            local negative_weight = allocation_targets[negative_index].weight.negative
            allocation_targets[negative_index].negative = allocation_targets[negative_index].negative + negative_weight
            negative_points = negative_points - negative_weight
        end
        -- for i = 1, negative_points, 1 do
        --     local negative_index = negative_allocation_indices[math.random(n_negative_allocation_indices)]
        --     allocation_targets[negative_index].negative = allocation_targets[negative_index].negative + 1
        -- end
    else
        log("[WARN] Zero negative allocation indices selected.")
    end
end

local function allocate_points_by_weight(allocation_targets, positive_allocation_indices, negative_allocation_indices, positive_points, negative_points)
    local n_positive_allocation_indices = calculate_n_pairs(positive_allocation_indices)
    local n_negative_allocation_indices = calculate_n_pairs(negative_allocation_indices)
    if n_positive_allocation_indices then
        local weights = {}
        local sum = 0
        for _, index in pairs(n_positive_allocation_indices) do
            local weight = random.random()
            weights[index] = weight
            sum = sum + weight
        end
        for _, index in pairs(n_positive_allocation_indices) do
            weights[index] = weights[index]/sum
            allocation_targets[index].positive = positive_points*weights[index]
        end
    end
    if n_negative_allocation_indices then
        local weights = {}
        local sum = 0
        for _, index in pairs(n_negative_allocation_indices) do
            local weight = random.random()
            weights[index] = weight
            sum = sum + weight
        end
        for _, index in pairs(n_negative_allocation_indices) do
            weights[index] = weights[index]/sum
            allocation_targets[index].negative = negative_points*weights[index]
        end
    end
end

local function compute_alternate_value(args)
    local point_scale = args.point_scale or 13
    local factor = math.min(2, 2^(args.points_to_allocate.negative/point_scale))/math.min(2, 2^(args.points_to_allocate.positive/point_scale))
    local raw_value = args.initial_value*factor
    if args.larger_is_positive then
        raw_value = args.initial_value/factor
    end
    local corrected_value = math.min(math.max(args.min_value, round(raw_value, args.round_place)), 65535)
    local positive_delta = math.max(0, point_scale*math.log(args.initial_value/corrected_value, 2))
    local negative_delta = math.max(0, point_scale*math.log(corrected_value/args.initial_value, 2))
    if args.larger_is_positive then
        positive_delta, negative_delta = negative_delta, positive_delta
    end
    local new_positive = args.points_to_allocate.positive-positive_delta
    local new_negative = args.points_to_allocate.negative-negative_delta
    return corrected_value, new_positive, new_negative
end

local function modify_recipe_via_points(recipe, points_to_allocate)
    local recipe_allocation_targets = {}
    local unshareable_targets = {}
    local i = 1
    for _, ingredient in pairs(recipe.ingredients) do
        normalize_ingredient_in_place(ingredient)
        if ingredient.type == "fluid" or is_item_stackable(ingredient.name) then
            recipe_allocation_targets[i] = {positive=0, negative=0, ingredient=ingredient, weight=create_weight(1, 1)}
            unshareable_targets[i] = true
            i = i + 1
        end
    end
    if recipe.results then
        for _, result in pairs(recipe.results) do
            normalize_result_in_place(result)
            if result.type == "fluid" or is_item_stackable(result.name) then
                recipe_allocation_targets[i] = {positive=0, negative=0, result=result, weight=create_weight(1, 1)}
                unshareable_targets[i] = true
                i = i + 1
            end
        end
    else
        if is_item_stackable(recipe.result) then
            recipe_allocation_targets[i] = {positive=0, negative=0, single_result=true, weight=create_weight(1, 1)}
            unshareable_targets[i] = true
            i = i + 1
        end
    end
    recipe_allocation_targets[i] = {positive=0, negative=0, recipe_time=true, weight=create_weight(0.3, 2)}
    unshareable_targets[i] = true
    local positive_recipe_indices, negative_recipe_indices = determine_allocation_indices(recipe_allocation_targets, unshareable_targets)
    allocate_points(recipe_allocation_targets, positive_recipe_indices, negative_recipe_indices, points_to_allocate.positive, points_to_allocate.negative)
    for _, recipe_points_to_allocate in pairs(recipe_allocation_targets) do
        if recipe_points_to_allocate.recipe_time then
            if not recipe.energy_required then
                recipe.energy_required = 0.5
            end
            recipe.energy_required, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                = compute_alternate_value{initial_value=recipe.energy_required, points_to_allocate=recipe_points_to_allocate, round_place=1, min_value=0.1}
        else
            if recipe_points_to_allocate.ingredient then
                local ingredient = recipe_points_to_allocate.ingredient
                if ingredient.type == "fluid" then
                    ingredient.amount, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                        = compute_alternate_value{initial_value=ingredient.amount, points_to_allocate=recipe_points_to_allocate, round_place=1, min_value=0.1}
                else
                    normalize_ingredient_in_place(recipe_points_to_allocate.ingredient)
                    ingredient.amount, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                        = compute_alternate_value{initial_value=ingredient.amount, points_to_allocate=recipe_points_to_allocate, round_place=0, min_value=1}
                end
            else
                if recipe_points_to_allocate.single_result then
                    if not recipe.result_count then
                        recipe.result_count = 1
                    end
                    recipe.result_count, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                        = compute_alternate_value{initial_value=recipe.result_count, points_to_allocate=recipe_points_to_allocate, round_place=0, min_value=1, larger_is_positive=true}
                else
                    local result = recipe_points_to_allocate.result
                    if result.type == "fluid" then
                        if result.amount then
                            result.amount, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                                = compute_alternate_value{initial_value=result.amount, points_to_allocate=recipe_points_to_allocate, round_place=1, min_value=0.1, larger_is_positive=true}
                        else
                            local original_amount_min = result.amount_min
                            result.amount_min, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                                = compute_alternate_value{initial_value=result.amount_min, points_to_allocate=recipe_points_to_allocate, round_place=1, min_value=0.1, larger_is_positive=true}
                            result.amount_max = math.max(0.1, round(result.amount_max*(result.amount_min/original_amount_min), 1))
                        end
                    else
                        normalize_result_in_place(result)
                        if result.amount then
                            result.amount, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                                = compute_alternate_value{initial_value=result.amount, points_to_allocate=recipe_points_to_allocate, round_place=0, min_value=1, larger_is_positive=true} 
                        else
                            -- log(serpent.block(result))
                            local original_amount_min = result.amount_min
                            result.amount_min, recipe_points_to_allocate.positive, recipe_points_to_allocate.negative
                                = compute_alternate_value{initial_value=result.amount_min, points_to_allocate=recipe_points_to_allocate, round_place=0, min_value=1, larger_is_positive=true} 
                            result.amount_max = math.max(1, round(result.amount_max*(result.amount_min/original_amount_min)))
                        end
                    end
                end 
            end
        end
    end
    local remaining_points_to_allocate = {positive=0, negative=0}
    for _, recipe_points_remaining in pairs(recipe_allocation_targets) do
        remaining_points_to_allocate.positive = remaining_points_to_allocate.positive + recipe_points_remaining.positive
        remaining_points_to_allocate.negative = remaining_points_to_allocate.negative + recipe_points_remaining.negative
    end
    return remaining_points_to_allocate
end

local function modify_technology_alternate_via_points(alternate_technology, suffix, modify_technology_params)
    local point_values = {
        base=20,
        recipe=5,
        ingredient=5,
        result=5,
    }

    local function compute_recipe_points(recipe)
        local points = 0
        for _, ingredient in pairs(recipe.ingredients) do
            points = points + point_values.ingredient
        end
        if recipe.results then
            for _, result in pairs(recipe.results) do
                points = points + point_values.result
            end
        else
            points = points + point_values.result
        end
        return points
    end

    local maximum_positive_points = point_values.base
    local allocation_targets = {}
    local research_cost_identifier = "technology_research_cost"
    local research_time_identifier = "technology_research_time"
    if modify_technology_params then
        if not (alternate_technology.normal or alternate_technology.expensive) then
            if not alternate_technology.unit.count_formula then
                allocation_targets = {[research_cost_identifier]={positive=0, negative=0, weight=create_weight(1, 3)}, [research_time_identifier]={positive=0, negative=0, weight=create_weight(1, 3)}}
            end
        end
    end

    local alternate_recipes = {}

    if alternate_technology.effects then
        for _, effect in pairs(alternate_technology.effects) do
            if effect.type == "unlock-recipe" then
                maximum_positive_points = maximum_positive_points + point_values.recipe
                local alternate_recipe = table.deepcopy(data.raw["recipe"][effect.recipe])
                local alternate_recipe_name = alternate_recipe.name..suffix -- FIXME should use technology suffix
                alternate_recipe.name = alternate_recipe_name
                effect.recipe = alternate_recipe_name
                if not alternate_recipe.order then
                    alternate_recipe.order = string.sub(alternate_recipe_name, 1, 190)
                end
                alternate_recipe.order = string.sub(alternate_recipe.order, 1, 190)..suffix
                alternate_recipes[alternate_recipe_name] = alternate_recipe
                allocation_targets[alternate_recipe_name] = {positive=0, negative=0, weight=create_weight(1, 1)}
                if alternate_recipe.normal or alternate_recipe.expensive  then
                    local normal_points = 0
                    if alternate_recipe.normal then
                        normal_points = compute_recipe_points(alternate_recipe.normal)
                    end
                    local expensive_points = 0
                    if alternate_recipe.expensive then
                        expensive_points = compute_recipe_points(alternate_recipe.expensive)
                    end
                    maximum_positive_points = maximum_positive_points + (normal_points+expensive_points)/2
                else
                    maximum_positive_points = maximum_positive_points + compute_recipe_points(alternate_recipe)
                end
            end
        end
    end
    local initial_positive_points = math.random(math.ceil(maximum_positive_points*0.5), maximum_positive_points)
    local discrepancy_range = math.ceil(maximum_positive_points*0.03)
    local total_discrepancy = math.random(discrepancy_range)-(discrepancy_range/2)
    -- if total_discrepancy > initial_positive_points*0.07 then
    --     log("High discrepancy: "..discrepancy_range)
    -- end
    local initial_negative_points = initial_positive_points+total_discrepancy

    local positive_points = initial_positive_points
    local negative_points = initial_negative_points
    local i = 0
    local n_iterations = 40
    while (positive_points > 0.05*initial_positive_points or negative_points > 0.05*initial_negative_points) and i < n_iterations do
        local positive_allocation_indices, negative_allocation_indices = determine_allocation_indices(allocation_targets, {[research_cost_identifier]=true, [research_time_identifier]=true})
        -- if calculate_n_pairs(positive_allocation_indices) <= 0 or calculate_n_pairs(negative_allocation_indices) then
        --     -- log("Erroneous Technology: "..alternate_technology.name)
        --     -- log("Positive: "..serpent.dump(positive_allocation_indices))
        --     -- log("Negative: "..serpent.dump(negative_allocation_indices))
        -- end
        allocate_points(allocation_targets, positive_allocation_indices, negative_allocation_indices, positive_points, negative_points)
        -- log("# of positive indices: "..calculate_n_pairs(positive_allocation_indices))
    
        for allocation_target, points_to_allocate in pairs(allocation_targets) do
            if allocation_target == research_cost_identifier then
                alternate_technology.unit.count, points_to_allocate.positive, points_to_allocate.negative
                    = compute_alternate_value{points_to_allocate=points_to_allocate, initial_value=alternate_technology.unit.count, round_place=0, min_value=1, point_scale=10}
            else
                if allocation_target == research_time_identifier then
                    alternate_technology.unit.time, points_to_allocate.positive, points_to_allocate.negative
                        = compute_alternate_value{points_to_allocate=points_to_allocate, initial_value=alternate_technology.unit.time, round_place=0, min_value=1, point_scale=10}
                else
                    -- Recipe
                    local recipe = alternate_recipes[allocation_target]
                    if recipe.normal or recipe.expensive then
                        local remaining_normal_points_to_allocate = {positive=0, negative=0}
                        if recipe.normal then
                            remaining_normal_points_to_allocate = modify_recipe_via_points(recipe.normal, points_to_allocate)
                        end
                        local remaining_expensive_points_to_allocate = {positive=0, negative=0}
                        if recipe.expensive then
                            remaining_expensive_points_to_allocate = modify_recipe_via_points(recipe.expensive, points_to_allocate)
                        end
                        local remaining_points_to_allocate = {
                            positive=(remaining_normal_points_to_allocate.positive+remaining_expensive_points_to_allocate.positive)/2,
                            negative=(remaining_normal_points_to_allocate.negative+remaining_expensive_points_to_allocate.negative)/2
                        }
                        points_to_allocate.positive = remaining_points_to_allocate.positive
                        points_to_allocate.negative = remaining_points_to_allocate.negative
                    else
                        local remaining_points_to_allocate = modify_recipe_via_points(recipe, points_to_allocate)
                        points_to_allocate.positive = remaining_points_to_allocate.positive
                        points_to_allocate.negative = remaining_points_to_allocate.negative
                    end
                end
            end
        end
        local positive_points_remaining = 0
        local negative_points_remaining = 0
        for _, points_to_allocate in pairs(allocation_targets) do
            positive_points_remaining = positive_points_remaining + points_to_allocate.positive
            negative_points_remaining = negative_points_remaining + points_to_allocate.negative
            points_to_allocate.positive = 0
            points_to_allocate.negative = 0
        end
        if positive_points_remaining < 0 then
            negative_points_remaining = negative_points_remaining + (-positive_points_remaining)
            positive_points_remaining = 0
        end
        if negative_points_remaining < 0 then
            positive_points_remaining = positive_points_remaining + (-negative_points_remaining)
            negative_points_remaining = 0
        end
        positive_points = positive_points_remaining
        negative_points = negative_points_remaining
        i = i + 1
    end
    if (positive_points > 10) then
        log("Excess positive points left over. Initial positive: "..tostring(initial_positive_points.."; final positive: "..tostring(positive_points)))
    end
    if (negative_points > 10) then
        log("Excess negative points left over. Initial negative: "..tostring(initial_negative_points.."; final negative: "..tostring(negative_points)))
    end
    local approximate_positive_allocated = initial_positive_points-positive_points
    local approximate_negative_allocated = initial_negative_points-negative_points
    if math.abs(approximate_negative_allocated-approximate_positive_allocated) > 5 then
        log("Discrepancy between positive and negative points allocated. Positive points: "..tostring(positive_points).."; negative points: "..tostring(negative_points).."; total discrepancy: "..tostring(math.abs(approximate_negative_allocated-approximate_positive_allocated)))
    end
    for _, recipe in pairs(alternate_recipes) do
        data:extend{recipe}
    end
end

local function generate_all_alternates()
    local recipe_database = {}
    math.randomseed(1, 2)
    local function generate_alternate(technology, i, modify_technology_params)
        local alternate_technology = table.deepcopy(technology)
        local suffix = "_"..alternate_constants.alternate_technology_code..tostring(i).."_"
        alternate_technology.name = alternate_technology.name..suffix
        if not alternate_technology.localised_name then
            alternate_technology.localised_name = {"technology-name."..technology.name}
        end
        alternate_technology.localised_name = {"", alternate_technology.localised_name, " ",  {"research-challenges.alternate", i}}

        -- alternate_technology.localised_name = {"?", alternate_technology.localised_name, {alternate_constants.technology_set_code, technology.name, alternate_constants.alternate_technology_code, i}}
        if not alternate_technology.localised_description then
            alternate_technology.localised_description = {"technology-description."..technology.name}
        end
        alternate_technology.order = alternate_technology.order..suffix
        log("Alternate technology: "..alternate_technology.name.."; order="..alternate_technology.order)
        -- modify_technology_alternate_initial(alternate_technology, suffix)
        modify_technology_alternate_via_points(alternate_technology, suffix, modify_technology_params)
        -- -- Vary effects
        -- local net_change = 0 -- How "good" a given alternate is compared to the baseline
        -- if alternate_technology.effects then
        --     for _, effect in pairs(alternate_technology.effects) do
        --         if effect.type == "unlock-recipe" then
        --             -- TODO Special handling for recipes unlocked by multiple technologies
        --             if (not recipe_database[effect.recipe] or recipe_database[effect.recipe] == technology.name) then
        --                 recipe_database[effect.recipe] = technology.name
        --                 local alternate_recipe = table.deepcopy(data.raw["recipe"][effect.recipe])
        --                 local alternate_recipe_name = alternate_recipe.name..suffix
        --                 alternate_recipe.name = alternate_recipe_name
        --                 effect.recipe = alternate_recipe_name
        --                 if not alternate_recipe.order then
        --                     alternate_recipe.order = string.sub(alternate_recipe.name, 1, 190)
        --                 end
        --                 alternate_recipe.order = string.sub(alternate_recipe.order, 1, 190)..suffix
        --                 if alternate_recipe.normal or alternate_recipe.expensive then
        --                     local normal_net_change = net_change
        --                     if alternate_recipe.normal then
        --                         normal_net_change = modify_alternate_recipe(alternate_recipe.normal, net_change)
        --                     end
        --                     local expensive_net_change = net_change
        --                     if alternate_recipe.expensive then
        --                         expensive_net_change = modify_alternate_recipe(alternate_recipe.expensive, net_change)
        --                     end
        --                     net_change = (normal_net_change+expensive_net_change)/2
        --                 else
        --                     net_change = modify_alternate_recipe(alternate_recipe, net_change)
        --                 end
        --                 log("Final net_change: "..tostring(net_change))
        --                 data:extend{alternate_recipe}
        --             end
        --         end
        --     end
        -- end
        
        -- if not (alternate_technology.normal or alternate_technology.expensive) then -- TODO Special handling for normal/expensive modes
        --     if not alternate_technology.unit.count_formula then -- TODO Special handling for formula-based research costs
        --         local count_power = random_float_around_center_point(net_change)
        --         local raw_count = (2^count_power)*alternate_technology.unit.count
        --         local corrected_count = math.max(1, round(raw_count))
        --         local effective_count_power = math.log(corrected_count/alternate_technology.unit.count, 2)
        --         alternate_technology.unit.count = corrected_count
        --         net_change = net_change - effective_count_power/2

        --         local time_power = random_float_around_center_point(net_change)
        --         local raw_time = (2^time_power)*alternate_technology.unit.time
        --         local corrected_time = math.max(0.1, round(raw_time, 1))
        --         local effective_time_power = math.log(corrected_time/alternate_technology.unit.time, 2)
        --         alternate_technology.unit.time = corrected_time
        --         net_change = net_change - effective_time_power/4
        --     end
        -- end
        log("Order for alternate technology "..alternate_technology.name.." is "..alternate_technology.order..".")
        return alternate_technology
    end
    -- Create a set of technology alternates
    local function create_technology_set(technology, is_initial)
        is_initial = is_initial or false
        local technology_set = {
            core = technology,
            alternates = {},
            initial = is_initial,
            set_name = technology.name
        }
        local technology_set_names_only = {
            core = technology_set.core.name,
            alternates = {},
            initial = is_initial,
            set_name = technology.name
        }
        for i = 1, 2, 1 do
            local alternate_technology = generate_alternate(technology, i, not is_initial)
            table.insert(technology_set.alternates, alternate_technology)
            table.insert(technology_set_names_only.alternates, alternate_technology.name)
        end
        local set_info_dummy_technology = table.deepcopy(technology)
        set_info_dummy_technology.name = "_DUMMY_"..set_info_dummy_technology.name
        technology_set_names_only.set_info_dummy_technology = set_info_dummy_technology.name
        set_info_dummy_technology.localised_name = {"?", "DUMMY", fragment_string(serpent.dump(technology_set_names_only))}
        set_info_dummy_technology.enabled = false
        set_info_dummy_technology.visible_when_disabled = false
        set_info_dummy_technology.effects = nil
        technology_set.set_info_dummy_technology = set_info_dummy_technology


        local orig_technology_name = technology.name
        if not technology.localised_name then
            technology.localised_name = {"", {"technology-name."..orig_technology_name}, " (Core)"}
        end
        -- ensure_order_exists(technology)
        -- technology.order = alternate_constants.core_technology_code.."_"..technology.order
        -- technology.localised_name = {"?", technology.localised_name, {alternate_constants.technology_set_code, technology.name, alternate_constants.core_technology_code}}
        technology.visible_when_disabled = true
        technology.enabled = false
        technology.effects = nil
        -- data:extend{technology} -- Seems to be necessary to update the prototype stored in data.raw
        -- data:extend{set_info_dummy_technology}
        -- data:extend(technology_set.alternates)
        return technology_set
    end

    -- Create baseline technologies with the starter recipes, so we can then create alternates for each of them.
    local initial_technology_base = table.deepcopy(data.raw["technology"]["automation"])
    initial_technology_base.name = "zero-cost"
    initial_technology_base.effects = nil
    initial_technology_base.enabled = true
    initial_technology_base.localised_name = nil
    initial_technology_base.localised_description = nil
    initial_technology_base.unit.ingredients = {}
    initial_technology_base.unit.time = 1
    initial_technology_base.unit.count = 1
    -- data:extend{initial_technology_base}
    local function create_initial_recipe_technology_baseline(technology_name, item_for_icon, recipe_names)
        local initial_technology = table.deepcopy(initial_technology_base)
        initial_technology.effects = {}
        for _, recipe_name in pairs(recipe_names) do
            table.insert(initial_technology.effects, create_recipe_unlock(recipe_name))
        end
        initial_technology.name = "research-challenges-"..technology_name
        initial_technology.order = string.sub(initial_technology.name, 1, 190)
        initial_technology.icons = nil
        initial_technology.icon = item_for_icon.icon
        initial_technology.icon_size = item_for_icon.icon_size
        -- initial_technology.localised_name = {"technology-name.research-challenges."..technology_name}
        -- initial_technology.localised_description = {"technology-description.research-challenges."..technology_name}
        return initial_technology
    end
    local initial_baselines = {
        smelting = create_initial_recipe_technology_baseline("initial-smelting", data.raw["item"]["stone-furnace"], {"iron-plate", "copper-plate", "stone-brick", "stone-furnace"}),
        intermediates = create_initial_recipe_technology_baseline("initial-intermediates", data.raw["item"]["iron-gear-wheel"], {"copper-cable", "iron-stick", "iron-gear-wheel", "electronic-circuit"}),
        science = create_initial_recipe_technology_baseline("initial-science", data.raw["item"]["lab"], {"lab", "automation-science-pack"}),
        transport_logistics = create_initial_recipe_technology_baseline("initial-transport-logistics", data.raw["item"]["transport-belt"], {"transport-belt", "inserter", "burner-inserter", "pipe", "pipe-to-ground"}),
        storage = create_initial_recipe_technology_baseline("initial-storage", data.raw["item"]["wooden-chest"], {"wooden-chest", "iron-chest"}),
        military = create_initial_recipe_technology_baseline("initial-military", data.raw["gun"]["pistol"], {"pistol", "firearm-magazine", "light-armor", "radar", "repair-pack"}),
        power = create_initial_recipe_technology_baseline("initial-power", data.raw["item"]["steam-engine"], {"small-electric-pole", "offshore-pump", "steam-engine", "boiler"}),
        mining = create_initial_recipe_technology_baseline("initial-mining", data.raw["item"]["burner-mining-drill"], {"burner-mining-drill", "electric-mining-drill"})
    }
    local initial_baselines_names = {}
    for _, initial_baseline in pairs(initial_baselines) do
        table.insert(initial_baselines_names, initial_baseline.name)
    end
    -- for _, technology in pairs(data.raw["technology"]) do
    --     if not has_levels(technology) then -- TODO Special handling might be needed
    --         if not technology.prerequisites or technology.prerequisites == {} then
    --             technology.prerequisites = initial_baselines_names
    --         end
    --     end
    -- end

    -- Create main technology alternates
    for _, technology in pairs(table.deepcopy(data.raw["technology"])) do
        if not has_levels(technology) then -- TODO Special handling might be needed
            local technology_set = create_technology_set(technology)
            -- technology_set.core.enabled = false
            -- technology_set.set_info_dummy_technology.enabled = false
            -- for _, alternate_technology in pairs(technology_set.alternates) do
            --     alternate_technology.enabled = false
            -- end
            data:extend{technology_set.core}
            data:extend{technology_set.set_info_dummy_technology}
            data:extend(technology_set.alternates)
        else
            log("Has levels: "..technology.name)
        end
    end
    -- for _, initial_technology_baseline in pairs(initial_baselines) do
    --     for _, effect in pairs(initial_technology_baseline.effects) do
    --         data.raw["recipe"][effect.recipe].enabled = false
    --     end
    --     -- generate_alternates_for_technology(initial_technology_baseline)
    --     -- data:extend{initial_technology_baseline}
    -- end
    -- Create initial technology alternates
    for _, initial_technology_baseline in pairs(initial_baselines) do
        for _, effect in pairs(initial_technology_baseline.effects) do
            local recipe = data.raw["recipe"][effect.recipe]
            recipe.enabled = false
            if recipe.normal then
                recipe.normal.enabled = false
            end
            if recipe.expensive then
                recipe.expensive.enabled = false
            end
        end
        local technology_set = create_technology_set(initial_technology_baseline, true)
        for _, alternate in pairs(technology_set.alternates) do
            alternate.unit.time = 1
            alternate.unit.cost = 1
            data:extend{alternate}
        end
        data:extend{technology_set.core}
        data:extend{technology_set.set_info_dummy_technology}
        data:extend(technology_set.alternates)
    end

    for k, _ in pairs(data.raw) do
        log(k)
    end
    local initial_lab = {
        name=alternate_constants.initial_technology_lab_name,
        type = "lab",
        energy_usage = "1W",
        energy_source = {type="void"},
        on_animation = data.raw["lab"]["lab"].on_animation,
        off_animation = data.raw["lab"]["lab"].off_animation,
        inputs={},
        researching_speed = 1000,
    }
    initial_lab.on_animation.tint = {r=0, g=0, b=0, a=1}
    initial_lab.off_animation.tint = {r=0, g=0, b=0, a=1}
    data:extend{initial_lab}
    -- log(serpent.block(data.raw["recipe"]))
    -- error("ASDF")
end

local exports = {
    data_setup = generate_all_alternates
}

return exports