local lookup_table = require("research-challenges-util.lookup-table-with-default")

local default_time_limit = 60 -- minutes
local specific_time_limits = {}
specific_time_limits.optics = 1
local exports = {
    time_limits_lookup_table = lookup_table.create_lookup_table{default=default_time_limit, specific_values=specific_time_limits}
}

return exports