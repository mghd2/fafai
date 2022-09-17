local MattBeginSession = import('/mods/TestAI/lua/Map/MapMarkers.lua').BeginSession
local MattOldBeginSession = BeginSession
function BeginSession()
    MattOldBeginSession()
    MattBeginSession()
end

local MattCreateMarker = import('/mods/TestAI/lua/Map/MapMarkers.lua').CreateMarker
local MattOldCreateResourceDeposit = CreateResourceDeposit
CreateResourceDeposit = function(t, x, y, z, size)
    MattCreateMarker(t, x, y, z, size) -- Making this first because it is in DilliDalli and I don't know why it's crashing otherwise
    MattOldCreateResourceDeposit(t, x, y, z, size)
end

-- Still not really sure why this one is needed.  Fields of Isis?
local MattSetPlayableRect = import('/mods/TestAI/lua/Map/MapMarkers.lua').SetPlayableRect
local MattOldSetPlayableRect = SetPlayableRect
SetPlayableRect = function(x0,z0,x1,z1)
    MattOldSetPlayableRect(x0,z0,x1,z1)
    MattSetPlayableRect(x0,z0,x1,z1)
end