local Squad = import('/mods/TestAI/lua/AI/Armies/Squad.lua').Squad

-- This Squad controls interceptors and ASFs
-- It's responsible for maintaining air superiority, and defending our other air units
AntiAir = Class(Squad) {
    New = function(self, army, zone)
        Squad.New(self, army, "AntiAir", zone)

        self.gather_pos = self.rally_pos  -- Save a safe spot near our base to go back to

        self:VisualizeTarget("aadd1111")
    end,

    -- Main problems
    -- Flying over MAA or static AA on the way to a good fight


    OnTick = function(self)
        local idle_fraction = self:GetUnitStates()
        if idle_fraction > 0.5 then
            local target_sq = self.map:FindBestFightFrom(self.map:OurBase(), 15, "Air", self.units, nil)
            if target_sq then
                self.target = target_sq.P
                LOG("Inty target "..repr(self.target))
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