local TestAITimerList = {}  -- Key is pop-tick, Value is a list of Timers
local TestAITimerCurrentTick = 1

function TimerThread(brain)
    while not brain:IsDefeated() do
        -- Pop timers off the list in case the callback triggers changes to other timers
        if TestAITimerList[TestAITimerCurrentTick] then
            local last_timer_index = 0
            repeat
                last_timer_index = table.getn(TestAITimerList[TestAITimerCurrentTick])
                if last_timer_index > 0 then
                    local t = TestAITimerList[TestAITimerCurrentTick][last_timer_index]
                    t.callback(unpack(t.args))
                    table.remove(TestAITimerList[TestAITimerCurrentTick], last_timer_index)
                end
            until last_timer_index < 2
        end

        WaitTicks(1)
        TestAITimerCurrentTick = TestAITimerCurrentTick + 1
    end
end

function InitTimers(brain)
    local timer_thread = ForkThread(TimerThread, brain)
    brain.Trash:Add(timer_thread)
end

Timer = Class({
    -- Ticks until pop; callback function, optional arguments follow
    New = function(self, ticks, callback, ...)
        self.callback = callback
        self.args = arg
        self.current_pop_tick = TestAITimerCurrentTick + ticks
        if TestAITimerList[self.current_pop_tick] == nil then
            TestAITimerList[self.current_pop_tick] = {}
        end
        table.insert(TestAITimerList[self.current_pop_tick], self)
        self.current_index = table.getn(TestAITimerList[self.current_pop_tick])
    end,

    Reset = function(self, ticks)
        table.remove(TestAITimerList[self.current_pop_tick], self.current_index)
        for i = self.current_index, table.getn(TestAITimerList[self.current_pop_tick]) do
            -- Fix up the index references for the following elements to match the preceeding table rebuild
            TestAITimerList[self.current_pop_tick][i].current_index = TestAITimerList[self.current_pop_tick][i].current_index - 1
        end
        self.current_pop_tick = TestAITimerCurrentTick + ticks
        if TestAITimerList[self.current_pop_tick] == nil then
            TestAITimerList[self.current_pop_tick] = {}
        end
        table.insert(TestAITimerList[TestAITimerCurrentTick + ticks], self)
        self.current_index = table.getn(TestAITimerList[self.current_pop_tick])
    end,
})


function someStuff(brain)
    local threads = {} -- {tick = {{callback, period}}}
    local tick = 1
    
    function AddLoopyThing(callback, period)
        if not threads[tick + period] then
            threads[tick + period] = {}
        end
        table.insert(threads[tick + period], {callback, period})
    end
    
    while not brain:IsDefeated() do
        if threads[tick] then
            for _, t in threads[tick] do
                
            end
        end
        threads[tick] = nil
        tick = tick + 1
        WaitTicks(1)
    end
end
