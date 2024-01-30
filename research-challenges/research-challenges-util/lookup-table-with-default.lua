local function create_lookup_table(args)
    if not type(args) == "table" then
        error("Arguments should be passed as a single table.")
    end
    if not args.default or not args.specific_values or not type(args.specific_values) == "table" then
        error("Invalid lookup table parameters passed. Lookup table received:\n"..serpent.block(args))
    end
    local lookup_table = {
        default=args.default,
        specific_values=args.specific_values
    }
    lookup_table.get_value = function(key)
        local value = lookup_table.specific_values[key]
        if not value then
            value = lookup_table.default
        end
        return value
    end
    return lookup_table
end

local exports = {
    create_lookup_table = create_lookup_table
}

return exports