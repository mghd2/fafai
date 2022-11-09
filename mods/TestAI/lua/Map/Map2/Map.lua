local floor = math.floor

---@class Map
---@field minX number The smallest x co-ordinate of the playable area
---@field minZ number The smallest z co-ordinate of the playable area
---@field maxI number The x size of the playable area counting from minX
---@field maxJ number The z size of the playable area counting from minZ
---@field grid1 GridEntry
---@field grid8 GridEntry
---@field grid64 GridEntry
Map = ClassSimple({
    ---@param self Map
    __init = function(self)
        self.baseX = 0
        self.baseZ = 0
        self.maxI = 0
        self.maxJ = 0
        self.grid1 = {}
        self.grid8 = {}
        self.grid64 = {}
    end,

    ---@param self Map
    ---@param position table {x, _, z}
    ---@param size integer Grid size; one of {1, 8, 64}
    ---@return GridEntry entry Or nil if outside the playable area
    GetEntryFromPosition = function(self, position, size)
        local i = floor(position[1] - self.minX)
        local j = floor(position[3] - self.minZ)
        if i < 0 or j < 0 or i > self.maxI or j > self.maxJ then
            return nil
        end

        if size == 1 then
            return self.grid1[i][j]
        elseif size == 8 then
            return self.grid8[floor(i/8)][floor(j/8)]
        else
            return self.grid8[floor(i/64)][floor(j/64)]
        end
    end,



})

-- Note: this class isn't actually used - it just provides help text
---@class GridEntry
-- These fields are common to all gridentries
-- An 81x81 map is 4096x4096
---@field Id integer Unique identifier: gridsize*67108864+I*8192+J
-- I is 
---@field Pos table Position ({x, y, z}) in the centre of this GridEntry
---@field vPathLand View
---@field vPathHover View
---@field vPathNaval View
---@field vPathAmphib View
---@field vPathAir View
-- These fields are the possible views: not all may exist in every GridEntry
---@field vThreatAir View Threat from the perspective of air units
---@field vThreatSurface View Threat from the perspective of land units
---@field vThreatSub View Threat from the perspective of submarines
GridEntry = ClassSimple({})

-- Note: this class isn't actually used - it just provides help text
---@class View
View = ClassSimple({})
