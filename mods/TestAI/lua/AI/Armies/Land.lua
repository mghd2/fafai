local Army = import('/mods/TestAI/lua/AI/Armies/Army.lua').Army
local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat

local ResourceRaider = import('/mods/TestAI/lua/AI/Armies/LandSquads/ResourceRaider.lua').ResourceRaider
local LandDefense = import('/mods/TestAI/lua/AI/Armies/LandSquads/LandDefense.lua').LandDefense
local LandAttack = import('/mods/TestAI/lua/AI/Armies/LandSquads/LandAttack.lua').LandAttack

-- Do I want to allow armies to steal units from each other?
-- Or maybe one army can offer units up?

-- Maintain a group of units that moves around a zone attacking good targets
Land = Class(Army) {
    New = function(self, brain, zone)
        Army.New(
            self,
            brain,
            categories.FACTORY * categories.LAND,
            categories.LAND * categories.MOBILE - categories.COMMAND - categories.ENGINEER - categories.UNSELECTABLE,
            150,
            zone
        )

        -- Create multiple groups of different sizes
        self.resource_raiders = {}
        for i = 1, 3 do
            local rr = ResourceRaider()
            rr:New(self, 1)
            rr.weight = 1 / math.pow(2, i)
            table.insert(self.resource_raiders, rr)
        end

        self.land_defenses = {}
        for i = 1, 1 do  -- Trying just having one
            local ld = LandDefense()
            ld:New(self, 1)
            ld.weight = 1 / math.pow(2, i)
            table.insert(self.land_defenses, ld)
        end

        self.land_attack = LandAttack()
        self.land_attack:New(self, 1)
    end,


    -- Does not handle unit composition


    -- Do main combat stuff


    -- TODO: This is now a squad fnl

    -- OK, what will work...
    -- What does DD do?  It has zones (variable sized blobs on the map; somewhat sparse)
    -- Per group:
    -- Have a staging and target zone
    -- RetreatFunction() says "attack" or clear commands and retreat away from localThreatPos
    -- ZoneAttackFunction says "retreat" or if stronger than target zone "attack zone", else "goto staging"
    -- The zones can be blank; there's lots of code for that...
    -- It uses a kinda get threat in radius thing
    -- Also considers nearby allies
    -- Has a confidence stat that multiplies its strength
    UnitAdded = function(self, unit)
        LOG("New Land unit")
        -- Add unit to the smallest group
        local rand = RandomFloat(0, 1)
        if rand < 0.2 then
            -- TODO This sort encourages throwing more units into a squad that's being wiped out
            -- TODO: Also consider limiting surviving strength: the defense forces become unnecessarily large when they are safe
            table.sort(self.land_defenses, function(a, b) return table.getn(a.units) * a.weight < table.getn(b.units) * b.weight end)
            self.land_defenses[1]:AddUnit(unit)
            LOG("Added to defense")
        elseif rand < 0.4 then
            table.sort(self.resource_raiders, function(a, b) return table.getn(a.units) * a.weight < table.getn(b.units) * b.weight end)
            self.resource_raiders[1]:AddUnit(unit)
            LOG("Added to raiders")
        else
            self.land_attack:AddUnit(unit)
            LOG("Added to attack")
        end
    end,

    -- Do I need states for ACU hunting, or base flattening?
    SquadThread = function(self)
        local sampleFSM = FSM()
        sampleFSM:New(
            "Squad Member FSM",
            {               "1:Gathering",  "2:Advancing",  "3:Retreating", "4:Waiting",    "5:Fighting"},
            {
                UnitAdded=  {{1, "M"},      {},             {},             {},             {}},
                StuckTimer= {{},            {},             {},             {},             {}},
            },
            {
                M = function(p, u) LOG(p..u) end,
                N = function() LOG("Move individual units somewhere else") end,
            },
            "action param 1"
        )
        sampleFSM:Input("Added", u)


    end,


    -- TODO: Add a claim system for dealing with invaders

    -- TODO: Send tanks to an expansion to rally

    -- TODO: Don't attack move Harbies (they reclaim)

    -- If rallied units is too small, we might be streaming into death
    -- Ideally reset the pos then?

    -- self.rallied_units must have been updated before calling and must be non-empty
    PickAttackTarget = function(self)
        local army_pos = self:GetAveragePosition(self.rallied_units)
        local army_sq = self.map:GetSquare(army_pos)
        if not army_sq then
            return
        end
        self.army_pos = army_pos
        local square = self.map:FindBestFightFrom(army_pos, 2.5, "Land", self.rallied_units)
        if not square then
            local value_fn = function(sq)
                return table.getn(sq.MexesFree) * RandomFloat(10, 100)
            end
            local filter_fn = function(sq)
                return sq.Ratio > 0.2 and sq.Ratio < 0.8
            end
            -- Use a high speed to encourage picking a more distant square
            -- Ideally exclude near to pos instead
            square = self.map:FindBestSquareFrom(army_pos, 10, "Land", value_fn, 100, filter_fn)
        end
        if square then
            self.army_target = square.P
        end
    end,

    AttackThread = function(self)
        while not self.brain:IsDefeated() do
            self.rallied_units = self:UpdateUnitList(self.rallied_units)
            if not table.empty(self.rallied_units) and self.rallied_units[1]:IsIdleState() then
                self:PickAttackTarget()
                LOG("Attacking "..repr(self.army_target))
                IssueMove(self.rallied_units, self.army_target)
            end

            WaitTicks(127)
        end
    end,

}