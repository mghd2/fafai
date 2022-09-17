local Squad = import('/mods/TestAI/lua/AI/Armies/Squad.lua').Squad
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat

-- TODO Remove: just trying out different moves
local move_fn = function(squad, units, destination)
    IssueFormMove(units, destination, 'GrowthFormation', squad:EnemyBaseHeading())
end

-- This Squad attacks the enemy
LandAttack = Class(Squad) {
    New = function(self, army, zone)
        Squad.New(self, army, "LandAttack", zone)
        self.zone = zone

        self.unformed_units = {}
        self.unit_count_max = 0
        self:VisualizeTarget("aadd1111")

        -- TODO: Remove this, it's awful
        self.map.threat_map.squad_for_threat = self
    end,


-- What would a better way of targeting be?
-- Maybe a kind of find path to enemy base that's safeish?

    MonitorStrengthAround = function(self)
        if not self.rally_pos and self.target then
            return
        end

        -- Check the fight value 20 ahead of our current position towards the target
        local monitor_pos = self:GetPositionTowards(self.rally_pos, self.target)
        if monitor_pos then
            local sq = self.map:GetSquareNearbyOnLayer(monitor_pos, "Land", self.zone)
            local value = self.map:FightSquareValueRatio(sq, self.map:GetUnitsThreat(self.units))
            if value < -0.1 then  -- Small losses to (e.g.) bombers are OK
                -- TODO: Might not want to take very slightly positive fights...  Not worth a huge army trekking around to hunt scouts
                LOG("Squad in danger! ratio="..value)
                -- For now just retreat towards our base
                local behind = self:GetPositionTowards(self.rally_pos, self.map:OurBase())
                if behind then
                    LOG("Got somewhere to retreat to")
                    self.target = behind
                    IssueClearCommands(self.units)
                    move_fn(self, self.units, self.target)
                end
            end
        end
    end,

    OnTick = function(self)
        local idle_fraction = self:GetUnitStates()
        if not table.empty(self.units) and idle_fraction > 0.5 then
            self.unit_count_max = math.max(self.unit_count_max, table.getn(self.units))
            LOG("LandAttack moving")
            local army_sq = self.map:GetSquare(self.rally_pos)
            if not army_sq then
                return true
            end
            local minimum_ratio = army_sq.Ratio - 0.1  -- Don't retreat too much
            LOG("Current location known")
            local our_threat = self.map:GetUnitsThreat(self.units)
            -- This seems to have failed to find anywhere a bunch last game (from minute 4 to 12...)
            local value_fn = function(sq)
                return self.map:FightSquareValue(sq, our_threat)
            end
            local filter_fn = function(sq)
                -- Has a mex not built by us and doesn't retreat too much
                return sq.Ratio > minimum_ratio and sq.Claims["F"] < 1 and table.getn(sq.MexesFree) > 0
            end
            -- Ideally exclude near to pos instead
            local square = self.map:FindBestSquareFrom(self.rally_pos, 1.5, "Land", value_fn, 160, filter_fn)
            if square then
                LOG("Attacking somewhere new")
                -- For now, try intentionally not releasing the claim so we don't repeat our steps too much
                self.target_claim = self.map:GetClaim(square, "F", 1)
                self.target = square.P
            end
            IssueClearCommands(self.units)
            move_fn(self, self.units, self.target)
        end

        if table.getn(self.units) < 0.5 * self.unit_count_max then
            -- TODO: Use value not just unit count
            LOG("LandAttack has lost too much strength, changing to safe target")
            local value_fn = function(sq)
                local threat = self.map:EnemyThreatNearby(sq)
                return 100 / (1 + threat.HP[1])
            end
            local filter_fn = function(sq)
                return sq.Ratio > 0.1 and sq.Ratio < 0.25
            end
            local rally_sq = self.map:FindBestSquareFrom(self.map:OurBase(), 8, "Land", value_fn, 300, filter_fn)
            if rally_sq then
                LOG("Picked a new target")
                LOG("Target has Ratio "..rally_sq.Ratio)
                self.rally_pos = rally_sq.P
                self.target = self.rally_pos
                IssueClearCommands(self.units)
                IssueClearCommands(self.rallying_units)
                for _, u in self.rallying_units do
                    IssueMove({u}, self.rally_pos)
                end
                move_fn(self, self.units, self.target)
                self.unit_count_max = table.getn(self.units)
                self.target_claim = self.map:GetClaim(rally_sq, "F", 1)
            end
        end

        self:MonitorStrengthAround()

        if self.target_claim then
            self.map:RefreshClaim(self.target_claim)
        end

        return true
    end,

    UnitArrived = function(self, unit)
        -- Merge the unit into the formation if the formation is idle or we have 4 or more units not merged in
        if self:GetUnitStates() > 0.5 or table.getn(self.unformed_units) > 2 then
            self.unformed_units = {}
            move_fn(self, self.units, self.target)
        else
            IssueMove({unit}, self.target)
            table.insert(self.unformed_units, unit)
        end
    end,


}