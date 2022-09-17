local Squad = import('/mods/TestAI/lua/AI/Armies/Squad.lua').Squad

-- This Squad controls T1 bombers
-- It prioritizes defense, but may attack a bit
AntiGround = Class(Squad) {
    New = function(self, army, zone)
        Squad.New(self, army, "Bomber", zone)

        self.gather_pos = self.rally_pos  -- Save a safe spot near our base to go back to

        self:VisualizeTarget("aa11dd11")
    end,

    -- Main problems
    -- Flying over MAA or static AA on the way to a good fight


    OnTick = function(self)
        local idle_fraction = self:GetUnitStates()
        if idle_fraction > 0.5 then
            local filter_fn = function(sq)
                return sq.Ratio < 0.5
            end
            local target_sq = self.map:FindBestFightFrom(self.map:OurBase(), 10, "Air", self.units, filter_fn)
            if not target_sq and table.getn(self.units) > 5 then
                -- Didn't find somewhere on our part of the map to defend and we have a decent force built up
                LOG("Trying to find somewhere for bombers to attack")
                target_sq = self.map:FindBestFightFrom(self.map:OurBase(), 10, "Air", self.units, nil)
            end
            if target_sq then
                self.target = target_sq.P
                LOG("Bomber target "..repr(self.target))
                IssueFormAggressiveMove(self.units, self.target, "AttackFormation", 180)
            else
                self.target = self.gather_pos
                IssueMove(self.units, self.gather_pos)
            end
        end
        return true
    end,

    UnitArrived = function(self, unit)
        IssueMove({unit}, self.target)
    end,

}