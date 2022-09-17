local ConstructionManager = import('/mods/TestAI/lua/AI/Production/ConstructionManager.lua')
local EcoAllocator = import('/mods/TestAI/lua/AI/Production/EcoAllocator.lua')
local FSM = import('/mods/TestAI/lua/Utils/FSM.lua')
local Timer = import('/mods/TestAI/lua/Utils/Timer.lua')
local Air = import('/mods/TestAI/lua/AI/Armies/Air.lua')
local Land = import('/mods/TestAI/lua/AI/Armies/Land.lua')
local Map = import('/mods/TestAI/lua/Map/Map.lua')

TestBrain = Class({
    Start = function(self, aiBrain)
        self.aiBrain = aiBrain

        -- Initialize the timer list: must happen before any timers are created
        Timer.InitTimers(aiBrain)

        -- This does most of the actual work
        self.construction_manager = ConstructionManager.ConstructionManager()
        self.construction_manager:New(aiBrain)
        LOG("Started ConstructionManager")

        --EcoAllocator.InitAllocator(aiBrain)

        self.air = Air.Air()
        self.air:New(aiBrain)
        -- TODO: This call should probably be moved inside New
        self.construction_manager:RegisterUnitRecruiter(self.air, categories.FACTORY * categories.AIR, nil)
        LOG("Started Air")

        self.land = Land.Land()
        self.land:New(aiBrain)
        -- TODO: Stop using the recruiter class for this and use the below?
        --self.construction_manager:RegisterUnitRecruiter(self.ld, categories.FACTORY * categories.LAND, 1)
        LOG("Started Land Defense")

        -- TEMP
        self.map = Map.GetMap(aiBrain)

        -- TODO Reinstate if needed, but with less log spam
        --self.ProfileThread = ForkThread(TestBrain.ProfileLoop, self)  -- These args must be from the perspective of the main aiBrain
    end,
    ProfileLoop = function(self)
        -- It's not strictly tick scoped, because I don't know the ordering of threads
        local time = GetSystemTimeSecondsOnlyForProfileUse()
        while not self.aiBrain:IsDefeated() do
            local gcinfo = gcinfo()
--            local garbage = collectgarbage(0)  -- This would force a collection
            
            local new_time = GetSystemTimeSecondsOnlyForProfileUse()
            LOG("Profile results: tick took "..(new_time-time).." and garbage is "..repr(gcinfo))
            time = new_time
            WaitTicks(1)
        end
    end,
})

function StartBrain(aiBrain)
    LOG(aiBrain)
    local b = TestBrain()
    b:Start(aiBrain)
    return b
end