-- Tests ran when the game starts (called by the main AI)
function RunTests()
    RunEA = import('/mods/TestAI/lua/tests/test_allocator.lua').Run
    RunEA()
end

-- Tests ran with or without the game
function RunUTs()
    require('/mods/TestAI/lua/tests/test_eco.lua')
    Run()
end
RunUTs()