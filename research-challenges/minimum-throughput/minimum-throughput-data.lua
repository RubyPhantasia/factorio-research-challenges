local fractions = require("minimum-throughput-constants")
local general_util = require("research-challenges-util.general-util")


-- TODO Would like to include actual SPM cost in description, not just a fraction

local exports = {
    data_setup = function()
        general_util.append_to_all_technologies_descriptions("research-challenges.minimum-throughput", fractions.minimum_throughput_fractions_table.get_value)
    end
}

return exports