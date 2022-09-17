-- Functions for deciding places to attack / defend

function NewTargets(map)
    -- Record enemy starting positions
    map.targets.enemy_bases = {}
    for _, a in ListArmies() do
        local b = GetArmyBrain(a)
        if b and IsEnemy(b:GetArmyIndex(), map.brain:GetArmyIndex()) then
            local e_x, e_z = b:GetArmyStartPos()
            local e_y = GetTerrainHeight(e_x, e_z)
            table.insert(map.targets.enemy_bases, {e_x, e_y, e_z})
        end
    end




end

-- TODO: Move the other targets stuff out of the MapMarkers file to here

-- TODO: Filter targets by landzone

function GetAttackPath(map)
    return {{Position=map.targets.enemy_bases[1]}}
end