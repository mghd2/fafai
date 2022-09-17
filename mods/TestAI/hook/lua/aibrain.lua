local TestAIStartBrain = import('/mods/TestAI/lua/AI/brain.lua').StartBrain

-- The following hooks the AIBrain in such a way that it does nothing and never interferes
TestAIOldBrainClass = AIBrain
AIBrain = Class(TestAIOldBrainClass) {
    OnCreateAI = function(self, planName)
        TestAIOldBrainClass.OnCreateAI(self, planName)
        local personality = ScenarioInfo.ArmySetup[self.Name].AIPersonality
        if string.find(personality, 'estai') then
            self.TestAI = true
            self.SkirmishSystems = false  -- Prevent interference by standard AI functions
            LOG("TestAI detected: OnCreateAI")
        end
    end,
    InitialAIThread = function(self)
        if self.TestAI then
            WaitTicks(30)  -- Copied from InitialAIThread to allow the starting area to clear from the landing blast
            -- ^^ TODO: Test to make sure this is the same speed as a player can build at.
            LOG(self)
           self.TestBrain = TestAIStartBrain(self)
        else
            TestAIOldBrainClass.InitialAIThread(self)
        end
    end,
}

-- TODO: Hook wherever units get transferred around and clear out the TestAI variables
-- Might be best to also move them into a sub-table