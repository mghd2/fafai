-- Responsibilities: choke points, places to drop, ponds to make navy in, informing land / air bias

-- To find choke points, maybe I can calculate a bunch of unique A* paths from A to E.
-- I'll have to use start and end zones; and crossing over each other will be a bit of a pain
-- But if I can make it work...
-- Probably need to be able to push other paths over a bit

-- Warning: paths will be along the grid, so not very efficient
-- Return {<square> => {<predecessor on best path>, <number of steps}}
function CalculateDijkstraTree(map, start, layer)
    local start_time = GetSystemTimeSecondsOnlyForProfileUse()
    local spf_tree = {}
    spf_tree[start] = {nil, 0}





    local end_time = GetSystemTimeSecondsOnlyForProfileUse()
    LOG("Dijkstra run took "..(end_time - start_time))
    return spf_tree
end


