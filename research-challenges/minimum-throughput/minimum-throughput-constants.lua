local lookup_table_util = require("research-challenges-util.lookup-table-with-default")

-- Default minimum throughput per minute for a given technology is this times the technology's's cost.
local default_minimum_throughput_fraction = 0.01
local minimum_throughput_fractions = {}
minimum_throughput_fractions["optics"] = 0.1

local exports = {
    minimum_throughput_fractions_table = lookup_table_util.create_lookup_table{default=default_minimum_throughput_fraction, specific_values=minimum_throughput_fractions}
}

return exports