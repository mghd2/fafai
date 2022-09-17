local Map = import('/mods/TestAI/lua/Map/Map.lua')
local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')

Expander = Class({
    New = function(self, brain)
        self.brain = brain
        self.map = Map.GetMap(brain)

    end,

    -- TODO: Don't send engineers into PD to get reclaim (e.g. Vya-3)

    -- For now, Expanding engineers will get reclaim and mexes; value of reclaim weighted by parameter.

    -- How to keep track of which expanding engineer is best to get something?
    -- Is there a good way to get a backup engineer sent?  Or escort if needed?

    -- Returns a Task to expand to an unclaimed mex or reclaim, and claims that mex; or nil
    -- I'm not proud of the extra param...
    -- TODO: Consider the distance away the engineer is vs other engineers that will become ready
    Expand = function(self, engineer, done_fn, reclaim_weight, max_distance)
        local pos = engineer:GetPosition()
        local value_fn = function(square)
            -- Unclaimed reclaim mass plus unclaimed mex value
            -- MEX_VALUE is 500 and HYDRO_VALUE is 300
            return (1 - square.Claims["R"]) *
                (square.Reclaim.M * reclaim_weight +
                500 * table.getn(square.MexesFree) +
                300 * table.getn(square.HydrosFree))
        end

        local square, value = self.map:FindBestSquareFrom(pos, 2, "Hover", value_fn, max_distance, nil)
        if square then
            LOG("Expanding to "..repr(square.P).." which has value "..value)
            local mex_done = function(success)
                -- Don't unclaim resources if we failed: for markers the free monitoring thread needs time to catch them
                if done_fn then
                    done_fn(success)
                end
            end
            return Task.CreateTask(self.brain, "", mex_done, square)
        end
        return nil
    end,

})