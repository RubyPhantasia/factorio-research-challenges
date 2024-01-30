local event_handler = require("control-event-handler")

local modules = {
    {enabled=settings.startup["research-challenges-minimum-throughput-enabled"].value, name="Minimum Throughput", handler_module=require("minimum-throughput.minimum-throughput-handlers")},
    {enabled=settings.startup["research-challenges-time-limit-enabled"].value, name="Time Limit", handler_module=require("time-limit.time-limit-handlers")},
    {enabled=settings.startup["research-challenges-research-blitz-enabled"].value, name="Research Blitz", handler_module=require("research-blitz.research-blitz-handlers")},
    {enabled=false, name="Technology Alternates", handler_module=require("alternates.alternates-handlers")}
}

for _, module_entry in pairs(modules) do
    -- log("Hello")
    if module_entry.enabled then
        log("Registering module: "..module_entry.name)
        event_handler.register_active_module(module_entry.handler_module)
    end
end