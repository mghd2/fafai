local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')
local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local EcoRequestor = import('/mods/TestAI/lua/AI/Production/EcoAllocator.lua').EcoRequestor

Building = Class({

    -- bp refers to the list in Task.lua: e.g. MexT1
    New = function(self, bp, priority)



        self.requestor = EcoRequestor(min_val, priority, assign_cb, self)
        self.requestor:New()

    end,





})



local radar = Building()
radar:New(BP.RadarT1, 100)


-- How do I want to represent a base?
-- I guess I'll have a file for a main base, a file for a firebase, naval production, proxy, etc.
-- Some things I want to have a max count for; some things proportional to overall investment (shields, AA)
-- 