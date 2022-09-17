local Mapping = import('/mods/TestAI/lua/Map/MapMarkers.lua')
local Army = import('/mods/TestAI/lua/AI/Armies/Army.lua').Army
local BP = import('/mods/TestAI/lua/AI/Production/Task.lua').BP
local CompareBPUnit = import('/mods/TestAI/lua/AI/Production/Task.lua').CompareBPUnit
local RandomFloat = import('/lua/utilities.lua').GetRandomFloat

local AntiAir = import('/mods/TestAI/lua/AI/Armies/AirSquads/AntiAir.lua').AntiAir
local AntiGround = import('/mods/TestAI/lua/AI/Armies/AirSquads/AntiGround.lua').AntiGround

-- The Air is supposed to use and micro air units
Air = Class(Army) {
    New = function(self, brain)
        Army.New(
            self,
            brain,
            categories.FACTORY * categories.AIR,
            categories.AIR * categories.MOBILE - categories.UNSELECTABLE,
            100,
            nil
        )

        self.state = 1

        self.aa = AntiAir()
        self.aa:New(self, 1)

        self.ag = AntiGround()
        self.ag:New(self, 1)
    end,

    --[[
        FSM states: Similar, Superior, Inferior

        See attacking bomber: similar: 1 respond; superior: slightly bigger response; inferior: respond if safe (prefer near ground based AA)

    ]]

    -- Returns {Unit=<unit from the BP list>, Priority=<number>}
    ChooseBuildUnit = function(self, factory)
        local ratio = self.old_map.threat:GetStrengthRatio(6)
        LOG("Think our air strength ratio is "..ratio)
        local bomber_chance = 0.3  -- Similar
        if ratio < 0.6 then  -- Inferior
            bomber_chance = 0.1
        elseif ratio > 1.6 then  -- Superior
            bomber_chance = 0.6
        end
        if RandomFloat(0.0, 1.0) > bomber_chance then
            return {Unit=BP.IntyT1, Priority=100}
        else
            return {Unit=BP.BomberT1, Priority=100}
        end
    end,

    UnitAdded = function(self, unit)
        if CompareBPUnit(BP.IntyT1, unit) then
            LOG("Added unit is an inty")
            self.aa:AddUnit(unit)
        elseif CompareBPUnit(BP.BomberT1, unit) then
            LOG("Added unit is a bomber")
            self.ag:AddUnit(unit)
        end
    end,
}