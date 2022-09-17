Engineer = Class({

    New = function(self)
        self.state = "Idle"  -- Idle|Building|Assisting|Reclaiming
        self.target_location = {}  -- Where we want to move to
        self.total_reclaim_value = 0  -- Mass = 1, Energy = 0.1

    end,

    -- What do I actually need?  Is this going to just handle executing orders for a single engy?
    -- That's probably a reasonable scope
    -- There's also lots of logic for things like assistance I guess

    -- Monitor its engineers


    -- The basemanager should probably pick the engineer partially based on position
    BuildStructure = function(self, position)
        -- Do we need to get the bp?

        -- Placement: defenses outside, etc

    end,

    Reclaim = function(self)

    end,

    CombatMicro = function(self, threats)


    end,
})
