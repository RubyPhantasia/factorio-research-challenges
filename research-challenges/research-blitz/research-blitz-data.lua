local research_blitz_time_limits = require("research-blitz-constants")
local general_util = require("research-challenges-util.general-util")


local exports = {
    data_setup = function()
        general_util.append_to_all_technologies_descriptions("research-challenges.research-blitz",
                                                                research_blitz_time_limits.time_limit_lookup_table.get_value)
    end
}

return exports