local registered_modules = {}

-- For all actual handler functions.
local nth_tick_handlers = {}

local handler_factory_table = {}

local init_handlers = {}
local event_handlers = {}

local fetch_nth_tick_data_and_handlers
local add_nth_tick_handler
local remove_nth_tick_handler
local add_timer
local remove_timer

local function register_handler_factory(handler_name, factory)
    handler_factory_table[handler_name] = factory
end

local function create_handler(handler_name, handler_data)
    if not handler_factory_table[handler_name] then
        error("Tried to create a non-existent handler. Handler name: "..handler_name.."; handler data: "..serpent.block(handler_data))
    end
    return handler_factory_table[handler_name](handler_data)
end

local function unregister_nth_tick_handlers_if_empty(nth_tick)
    local handlers = (fetch_nth_tick_data_and_handlers(nth_tick)).handlers
    if #handlers.saved_handlers <= 0 and #handlers.timers <= 0 and #handlers.unsaved_handlers <= 0 then
        log("Removed nth_tick_handlers data entry for nth_tick "..tostring(nth_tick)..".")
        script.on_nth_tick(nth_tick, nil)
        global.nth_tick_handlers_data[nth_tick] = nil
        nth_tick_handlers[nth_tick] = nil
    end
end

-- Assumes that global.nth_tick_handlers_data[nth_tick] exists if and only if nth_tick_handlers[nth_tick] exists, and that
--  nth_tick_handlers[nth_tick] only exists if and only if the nth_tick handler has been registered with the script.
local function fetch_nth_tick_data(nth_tick)
    if not global.nth_tick_handlers_data[nth_tick] then
        log("Created nth_tick_handlers_data entry for nth_tick "..tostring(nth_tick)..".")
        global.nth_tick_handlers_data[nth_tick] = {
            next_id = 1,
            handlers_data = {},
            timers_data = {},
        }
    end
    return global.nth_tick_handlers_data[nth_tick]
end

local function fetch_nth_tick_handlers(nth_tick)
    if not nth_tick_handlers[nth_tick] then
        log("Created nth_tick_handlers entry for nth_tick "..tostring(nth_tick)..".")
        nth_tick_handlers[nth_tick] = {
            unsaved_handlers = {},
            saved_handlers = {},
            timers = {}
        }
        script.on_nth_tick(nth_tick, function(event)
            local handlers = nth_tick_handlers[nth_tick]
            for _, handler in pairs(handlers.unsaved_handlers) do
                handler(event)
            end
            for _, handler in pairs(handlers.saved_handlers) do
                handler(event)
            end
            if game.tick > 0 then
                log("Firing timers for nth_tick "..tostring(nth_tick))
                for _, timer in pairs(handlers.timers) do
                    timer(event)
                end
                handlers.timers = {}
            end
            unregister_nth_tick_handlers_if_empty(nth_tick)
        end)
    end
    return nth_tick_handlers[nth_tick]
end

function fetch_nth_tick_data_and_handlers(nth_tick)
    return {
        data=fetch_nth_tick_data(nth_tick),
        handlers=fetch_nth_tick_handlers(nth_tick)
    }
end

function add_nth_tick_handler(nth_tick, handler_name, handler_data)
    local handlers_info = fetch_nth_tick_data_and_handlers(nth_tick)
    local id = handlers_info.data.next_id
    handlers_info.data.next_id = handlers_info.data.next_id+1
    handlers_info.data.handlers_data[id] = {name=handler_name, data=handler_data}
    handlers_info.handlers.saved_handlers[id] = create_handler(handler_name, handler_data)
    return id
end

local function add_unsaved_nth_tick_handler(nth_tick, handler)
    local handlers = fetch_nth_tick_handlers(nth_tick)
    table.insert(handlers.unsaved_handlers, handler)
end

function add_timer(nth_tick, timer_name, timer_data)
    local handlers_info = fetch_nth_tick_data_and_handlers(nth_tick)
    local id = handlers_info.data.next_id
    handlers_info.data.next_id = handlers_info.data.next_id+1
    handlers_info.data.timers_data[id] = {name=timer_name, data=timer_data}
    handlers_info.handlers.timers[id] = create_handler(timer_name, timer_data)
    return id
end

function remove_nth_tick_handler(nth_tick, handler_id)
    local handlers_info = fetch_nth_tick_data_and_handlers(nth_tick)
    handlers_info.data.handlers_data[handler_id] = nil
    handlers_info.handlers.saved_handlers[handler_id] = nil
    unregister_nth_tick_handlers_if_empty(nth_tick)
end

function remove_timer(nth_tick, timer_id)
    local handlers_info = fetch_nth_tick_data_and_handlers(nth_tick)
    handlers_info.data.timers_data[timer_id] = nil
    handlers_info.handlers.timers[timer_id] = nil
    unregister_nth_tick_handlers_if_empty(nth_tick)
end

-- Module stuff

local function register_active_module(module)
    table.insert(registered_modules, module)
end

local function set_up_module(module)
    if module.init_handler then
        table.insert(init_handlers, module.init_handler)
    end
    if module.event_handlers then
        for event_type, handler in pairs(module.event_handlers) do
            if not event_handlers[event_type] then
                event_handlers[event_type] = {}
                script.on_event(event_type, function(event)
                    for _, handler in pairs(event_handlers[event_type]) do
                        handler(event)
                    end
                end)
            end
            table.insert(event_handlers[event_type], handler)
        end
    end
    if module.handler_factories then
        for handler_factory_name, handler_factory in pairs(module.handler_factories) do
            register_handler_factory(handler_factory_name, handler_factory)
        end
    end
    -- Non-conditional nth_tick handlers
    if module.non_conditional_nth_tick_handlers then
        for _, nth_tick_handler_entry in pairs(module.non_conditional_nth_tick_handlers) do
            add_unsaved_nth_tick_handler(nth_tick_handler_entry.nth_tick, nth_tick_handler_entry.handler)
        end
        log("Set up nth_tick_handlers.")
    end
end

local function set_up_all_registered_modules()
    for _, module in pairs(registered_modules) do
        set_up_module(module)
    end
end

script.on_init(function(event)
    global.nth_tick_handlers_data = {}
    set_up_all_registered_modules()
    for _, init_handler in pairs(init_handlers) do
        init_handler(event)
    end
end)

script.on_load(function(event)
    -- Recreate nth-tick handler functions
    set_up_all_registered_modules()
    for nth_tick, handlers in pairs(global.nth_tick_handlers_data) do
        for handler_id, handler_info in pairs(handlers.handlers_data) do
            nth_tick_handlers[nth_tick].handlers[handler_id] = create_handler(handler_info.name, handler_info.data)
        end
        for timer_id, timer_info in pairs(handlers.timers_data) do
            nth_tick_handlers[nth_tick].timers[timer_id] = create_handler(timer_info.name, timer_info.data)
        end
    end
end)

local exports = {
    register_handler_factory = register_handler_factory,
    add_nth_tick_handler = add_nth_tick_handler,
    add_timer = add_timer,
    remove_nth_tick_handler = remove_nth_tick_handler,
    remove_timer = remove_timer,
    register_active_module = register_active_module
}

return exports