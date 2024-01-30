local time_limits = require("time-limit-constants")
local general_util = require("research-challenges-util.general-util")



local exports = {
    data_setup = function()
        general_util.append_to_all_technologies_descriptions("research-challenges.time-limit", time_limits.time_limits_lookup_table.get_value)
    end
}

return exports