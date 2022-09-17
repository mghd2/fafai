local Squad = import('/mods/TestAI/lua/AI/Armies/Squad.lua').Squad
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat

-- This Squad raids resources (mostly mexes)
ResourceRaider = Class(Squad) {
    New = function(self, army, zone)
        Squad.New(self, army, "ResourceRaider", zone)
        
        self:VisualizeTarget("aa11dd11")
    end,

    OnTick = function(self)
        local idle_fraction = self:GetUnitStates()
        if not table.empty(self.units) and idle_fraction > 0.5 then
            LOG("Raider moving")
            local army_sq = self.map:GetSquare(self.rally_pos)
            if not army_sq then
                return true
            end
            local filter_fight_fn = function(sq)
                return sq.Claims["F"] < 1
            end
            local square = self.map:FindBestFightFrom(self.rally_pos, 2, "Land", self.units, filter_fight_fn)
            if not square then
                local value_fn = function(sq)
                    return table.getn(sq.MexesFree) * RandomFloat(10, 20)
                end
                local filter_fn = function(sq)
                    return sq.Ratio > 0.4 and sq.Ratio < 0.8 and sq.Claims["F"] < 1
                end
                -- Use a high speed to encourage picking a more distant square
                -- Ideally exclude near to pos instead
                square = self.map:FindBestSquareFrom(self.rally_pos, 3, "Land", value_fn, 80, filter_fn)
            end
            if square then
                -- For now, try intentionally not releasing the claim so we don't repeat our steps too much
                self.target_claim = self.map:GetClaim(square, "F", 1)
                self.target = square.P
            end
            IssueFormMove(self.units, self.target, 'AttackFormation', 0)
        end

        if self.target_claim then
            self.map:RefreshClaim(self.target_claim)
        end

        return true
    end,

    UnitArrived = function(self, unit)
        LOG("RR got a unit!")
        -- TODO: Random offset
        IssueMove({unit}, self.target)
    end,


}