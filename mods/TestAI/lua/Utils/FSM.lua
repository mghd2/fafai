FSM = Class({
    -- Initial state is always state 1
    -- Extra arguments are passed to actions
    New = function(self, name, states, table, actions, ...)
        self.name = name
        self.states = states  -- The names of the states
        self.table = table
        self.actions = actions
        self.args = arg

        self.state = 1
        self.running = false
        self.deferred_input_queue = {}
    end,

    -- Recursive calls are safe, and will be executed afterwards in the order received
    -- State changes happen after the actions are called
    -- Additional arguments will be passed to the actions after the per-FSM additional args
    Input = function(self, input, ...)
        if not self.running then
            self.running = true
            repeat
                local input_row = self.table[input]
                if input_row == nil then
                    LOG("Error: FSM ignoring unknown input: "..self.name.." input "..input)
                end
                local change = input_row[self.state]
                if change == nil then
                    LOG("Error: FSM ignoring invalid input: "..self.name.." input "..input.." in state "..self.state)
                else
                    local next_state = change[1]
                    local actions = change[2]
                    LOG(self.name.." input "..input.." state "..self.states[self.state].."->"..self.states[next_state])
                    
                    -- Call the actions
                    if actions then
                        for i=1, string.len(actions) do
                            local action = string.sub(actions, i, i)
                            self.actions[action](unpack(self.args), unpack(arg))
                        end
                    end

                    -- Update the state (might want to move this before the actions)
                    self.state = next_state
                end

                -- If we stored any recursive calls, execute the next one
                input = nil
                if table.getn(self.deferred_input_queue) > 0 then
                    input = table.remove(self.deferred_input_queue, 1)
                end
            until input == nil
            self.running = false
        else
            -- Store this recursive call
            table.insert(self.deferred_input_queue, input)
        end
    end,
})

-- How to include some weights in stuff?
-- At an overall strategy level I think I want to have StrategyManagers that can create Tasks
-- Somehow allocate funds between them, but also keep track of results and don't partially fund stuff
-- What about not letting a strat get distracted by a minor target?





-- Do I want to allow multiple actions?
-- Should I implement some kind of respin after some WaitTicks?

-- Example Usage:
--[[
local sampleFSM = FSM()
sampleFSM:New(
    "Squad Member FSM",
    {               "1:Gathering",  "2:Gathered"},
    {
        Added=      {{1, "M"},      {}},
        Arrived=    {{2},           {}},
        Lost=       {{},            {1, "M"}},
    },
    {
        M = function(p, u) LOG(p..u) end,
    },
    "action param 1"
)
sampleFSM:Input("Added", u)
sampleFSM:Input("Added", u)
sampleFSM:Input("Arrived")
sampleFSM:Input("Lost", u)
]]