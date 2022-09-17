local Squad = import('/mods/TestAI/lua/AI/Armies/Squad.lua').Squad
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat

-- This Squad defends our part of the map
LandDefense = Class(Squad) {
    New = function(self, army, zone)
        Squad.New(self, army, "LandDefense", zone)
        self.zone = zone
        -- TODO: Defend whole zone if no enemy starts exist in the zone

        self:VisualizeTarget("aa1111dd")
    end,

    OnTick = function(self)
        local idle_fraction = self:GetUnitStates()
        if not table.empty(self.units) and idle_fraction > 0.5 then
            LOG("LandDefense moving")
            local army_sq = self.map:GetSquare(self.rally_pos)
            if not army_sq then
                return true
            end
            LOG("Current location known")
            local value_fn = function(sq)
                local threat = self.map:EnemyThreatNearby(sq)
                if threat.HP[1] > 0 then
                    return table.getn(sq.Mexes)
                else
                    return 0
                end
            end
            local filter_fn = function(sq)
                -- Has a mex built by us on our half of the map and isn't claimed
                return sq.Ratio > 0.1 and sq.Ratio < 0.55 and sq.Claims["F"] < 1 and table.getn(sq.Mexes) > table.getn(sq.MexesFree)
            end
            -- Ideally exclude near to pos instead
            local square = self.map:FindBestSquareFrom(self.rally_pos, 5, "Land", value_fn, 160, filter_fn)
            if square then
                LOG("Defending somewhere new")
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
        -- TODO: Random offset
        IssueMove({unit}, self.target)
    end,


}