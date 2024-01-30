local minimum_throughput = require("minimum-throughput.minimum-throughput-data")
local time_limit = require("time-limit.time-limit-data")
local research_blitz = require("research-blitz.research-blitz-data")
local alternates = require("alternates.alternates-data")

if settings.startup["research-challenges-minimum-throughput-enabled"].value then
    minimum_throughput.data_setup()
end

if settings.startup["research-challenges-time-limit-enabled"].value then
    time_limit.data_setup()
end

if settings.startup["research-challenges-research-blitz-enabled"].value then
    research_blitz.data_setup()
end
-- alternates.data_setup()