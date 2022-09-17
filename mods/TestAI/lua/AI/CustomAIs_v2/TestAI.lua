--[[
    File    :   /lua/AI/CustomAIs_v2/TestAI.lua
    Author  :   SoftNoob
    Summary :
        Lists AIs to be included into the lobby, see /lua/AI/CustomAIs_v2/SorianAI.lua for another example.
        Loaded in by /lua/ui/lobby/aitypes.lua, this loads all lua files in /lua/AI/CustomAIs_v2/
]]

AI = {
	Name = 'TestAI',
	Version = '1',
	AIList = {
		{
			key = 'testai',
			name = '<LOC TestAI_0001>AI: Test',
		},
	},
	CheatAIList = {
		{
			key = 'testaicheat',
			name = '<LOC TestAI_0003>AIx: Test',
		},
	},
}