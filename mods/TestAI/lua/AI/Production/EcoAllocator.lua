-- The Eco[Provider|Allocator|Task] classes handle distributing economy around weighting by priority
-- They form a tree: EcoProvider -> EcoAllocator -> EcoAllocators -> EcoTasks
-- There can be many layers of EcoAllocators; although borrowing can be a bit weird across layers
-- It might be better to just flatten the layers, so there's one allocator and the other layers just multiple priorities through
-- TODO: Alternatively children could be asked to calculate their own ResourcesToFundingTicks,
-- taking into account each child onwards's own minimum cost (not using a low min cost from a low prio child, and a high
-- priority from a high min cost child).

-- What are the pros and cons on flattening all the code into the provider?
-- Simpler borrowing and maybe simpler code
-- Con: harder to deal with pausing stuff
-- Can I get rid of pausing?  I may have to deal with priority values of 0

-- Should this code be integrated with the eco prediction?  Maybe
-- If I can also consider spends per second and such; I could start things early etc
-- Perhaps building the exact right ratios isn't super important (can change target), but better eco is good


-- Can I put mexes and stuff through the EA?  Not sure...
-- How about a modified EA, where we have regular tasks with a priority; and also mexes, and also pgens
-- Mexes and pgens are created externally (without use of priority); they just steal resources at highest priority?
-- If they could accurately report back the eco they're consuming (rate and total?)
-- Can I modify this model to include rates?


local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')

local next_allocator_id = 1

EA2 = Class({
    AddChild = function(self, child, priority)
        self.total_child_priority = self.total_child_priority + priority
        self.parent:AddChild(child, priority / self.total_child_priority)
    end,

    
    -- Ideally I could separate recurring resources and instantaneous?
    -- A factory doesn't just want resources; it needs to fund its drain

    -- If the ecomanager could feed the allocators with the safe rate (100% generation + 20% reclaim?)
    -- Then we could use that to decide on factories?
    -- Prioritize giving non-factories the other stuff?
    ---@param massRecurring number The total amount of mass/tick that can be consumed
    -- The EcoAllocator is responsible for tracking how much recurring spend it already has
    GiveResources = function(self, massRecurring, energyRecurring, massExtra, energyExtra)
        -- Allocators can use recurring spend to make up for instant spend
        -- A challenge is keeping mass very close to 0 (factory efficiency vs unused mass)

        -- The problem is that we don't really know how fast we'll consume mass building something
        
    end,
})

ET = Class({


    GiveResources = function(self, res)

    end,
})


-- The cost of something is both immediate E and M, and ongoing draw

-- If we have 20% of our eco allocated to land production; that needs to be turned into the right number of factories
-- The Task (or maybe the land allocator for a zone) needs to figure that out

-- Maybe we use our mass generation + 10% of our average reclaim rate as the amount available for factories

LandAllocator = Class(EA2) {
    __init = function(self)
        self.mass_drain = 8  -- We have 2 T1 factories currently for example
        self.energy_drain = 40
        self.factoryCount = 2
    end,

    GiveResources = function(self, mass, energy)
        -- We're interested in either making units (not doing this implies pausing factories),
        -- or making additional factories
        -- The burstiness of GiveResources calls would break this - for drains we need to be called evenly every tick
        -- Say we tell an allocator what its per tick average is, and it can call back to consume that, reducing it's Gives?

    end,

    UpdateAverageResourceRate = function(self, massPerTick, energyPerTick)
        -- Here is where we decide if we want more factories or assistance
        if massPerTick > self.factoryCount * 4 then
            -- New factory
            -- TODO: Consider adjacency savings

        end
    end,
}


-- OLD

EcoAllocator = Class({
    New = function(self, priority)
        -- Allocator parameters used by the parent, call UpdateChildParameters on the parent to update these
        -- Must be set on all EcoAllocators or EcoTasks
        self.energy_ratio = 6
        self.minimum_resource_amount = 50
        self.paused = false
        self.priority = priority  -- Must not be negative
        self.id = 0

        self.parent = nil
        self.children_unpaused = {}  -- Keyed by the child id, value is {child, resource_balance, total_resources_to_funded}
        self.children_paused = {}  -- ^^
        self.total_child_priority = 0

    end,

    -- Add a child EcoAllocator
    AddChild = function(self, child)
        child.parent = self
        child.id = next_allocator_id
        next_allocator_id = next_allocator_id + 1
        self.children_unpaused[child.id] = {child, 0, 0}  -- It's always OK to add to unpaused, because it will be moved immediately after
        self:UpdateChildParameters()
    end,

    -- Called by a parent to assign a chunk of resources to this allocator
    -- Returns the amount of resources that will be consumed
    GiveResources = function(self, resources)
        if self.total_child_priority <= 0 then
            return 0
        end
        local total_held_resources = 0
        local total_spent = 0

        -- Distribute the resources between children and fund any children that meet their minimum
        -- TODO: Maybe include the paused resources?  Probably not ideal to go super negative
        -- ^^  : Maybe best is to redistribute paused resources beyond the minimum when it pauses?
        local give_resources = {}
        for id, v in self.children_unpaused do
            local child = v[1]
            -- Increase child resources
            v[2] = v[2] + resources * (child.priority / self.total_child_priority)

            -- Increase total held resources
            total_held_resources = total_held_resources + v[2]

            if v[2] >= child.minimum_resource_amount then
                -- We'll do the actual resource giving later so the children don't get a chance to
                -- re-entrantly change their requests until we've allocated fully.
                give_resources[id] = v[2]
            end

            -- Calculate total additional resources (for us) before this child will be funded
            v[3] = (child:CalculateEffectiveMinimum() - v[2]) * (self.total_child_priority / (child.priority + 0.00001))
        end

        -- Keep all amount spent tracking inside this function
        local function give_child_resources(id, r)
            -- Fund the child and adjust their balance (may go negative)
            -- Get a reference to the table before it maybe pauses re-entrantly
            local v = self.children_unpaused[id]
            local child = v[1]
            local total_spent_this_call = 0
            LOG("GCR")
            LOG(id)
            LOG(r)
            while r >= child.minimum_resource_amount and not child.paused do
                local amount_spent = child:GiveResources(r)
                LOG("Spent "..amount_spent)
                if amount_spent == 0 then
                    break
                end
                r = r - amount_spent
                total_spent_this_call = total_spent_this_call + amount_spent
                total_spent = total_spent + amount_spent
                total_held_resources = total_held_resources - amount_spent
                v[2] = v[2] - amount_spent
                v[3] = (child:CalculateEffectiveMinimum() - v[2]) * (self.total_child_priority / (child.priority + 0.00001))
            end
            return total_spent_this_call
        end

        -- Now give out all the resources
        for id, r in give_resources do
            give_child_resources(id, r)
        end

        -- If we have enough resources in total to fund the next thing we'd buy, but not allocated to it yet, fund it now
        -- This prevents the held resources from slowing overall production.
        -- e.g. A has prio 20, B and C prio 10: give 20 resources, A gets 10, B and C get 5, but A is funded (to -10) by borrowing
        while total_held_resources >= self.minimum_resource_amount do
            local best_child = nil
            local best_ticks = 9999
            for id, v in self.children_unpaused do
                if v[3] < best_ticks then
                    -- This child is the next to be funded
                    best_child = id
                    best_ticks = v[3]
                    if v[1].minimum_resource_amount > total_held_resources then
                        -- Only accelerate it if we can afford it though
                        best_child = nil
                    end
                end
            end
            if best_child then
                -- Only offer minimum amount, because each time we fund they fall further down the ranking
                LOG("Making a loan")
                LOG(repr(self.children_unpaused[best_child]))
                local amount_spent = give_child_resources(best_child, self.children_unpaused[best_child][1].minimum_resource_amount)
                if amount_spent == 0 then
                    break
                end
            else
                -- We often need to break because self.minimum_resource_amount may not be enough to fund the nearest thing
                break
            end
        end

        return total_spent
    end,

    -- Return the number of resources needed before this allocator would next be able to afford something
    CalculateEffectiveMinimum = function(self)
        local best_res = 99999  -- More than in GiveResources()
        for _, v in self.children_unpaused do
            local child = v[1]
            local child_cost = child:CalculateEffectiveMinimum() - v[2]  -- Allow for the current balance
            local child_eta = child_cost * (self.total_child_priority / (child.priority + 0.00001))
            if child_eta < best_res then
                best_res = child_eta
            end
        end
        return best_res
    end,

    -- Notify this EcoAllocator that a child may have changed its parameters
    -- Called whenever a child has been added, removed or updated to recalculate our own parameters
    UpdateChildParameters = function(self)
        -- Unpause the newly unpaused children, and pause the newly paused children
        local now_paused_children = {}
        local now_unpaused_children = {}
        for id, v in self.children_paused do
            if v[1].paused then
                now_paused_children[id] = v
            else
                now_unpaused_children[id] = v
            end
        end
        for id, v in self.children_unpaused do
            if v[1].paused then
                now_paused_children[id] = v
            else
                now_unpaused_children[id] = v
            end
        end
        self.children_paused = now_paused_children
        self.children_unpaused = now_unpaused_children  -- TODO: Here
 
        -- Recalculate our energy_ratio, minimum_resource_amount and total_child_priority
        self.minimum_resource_amount = 999999
        self.total_child_priority = 0
        local weighted_e_ratio = 0
        -- This iterates table keys and performs floating point calculations, but shouldn't cause desyncs
        -- because there's no error accumulation and the values are expected to be similar
        for id, v in self.children_unpaused do
            if v[1].minimum_resource_amount < self.minimum_resource_amount then
                self.minimum_resource_amount = v[1].minimum_resource_amount
            end
            weighted_e_ratio = weighted_e_ratio + v[1].priority * v[1].energy_ratio
            self.total_child_priority = self.total_child_priority + v[1].priority
        end
        if self.total_child_priority > 0 then
            self.energy_ratio = weighted_e_ratio / self.total_child_priority
        end

        -- Notify our parent that they may need to update parameters
        self.parent:UpdateChildParameters()
    end,
})

-- EcoProvider is used to feed resources into the allocators
-- It has a single child allocator that must not pause; which can then distribute between multiple children
EcoProvider = Class({
    New = function(self, child_allocator)
        self.allocator = child_allocator
        child_allocator.parent = self
    end,

    GiveResources = function(self, resources)
        self.allocator:GiveResources(resources)
    end,

    UpdateChildParameters = function(self)
    end,
})

-- Leaf node: build something specific
EcoTask = Class({
    New = function(self, bpid)
        -- Allocator parameters used by the parent, call UpdateChildParameters on the parent to update these
        -- Must be set on all EcoAllocators or EcoTasks
        -- TODO: Fill in energy ratio / minimum amount from the blueprint data
        self.energy_ratio = 6
        self.minimum_resource_amount = 50
        self.paused = false
        self.priority = 0  -- Must not be negative
        self.id = 0

    end,

    CalculateEffectiveMinimum = function(self)
        return self.minimum_resource_amount
    end,

    -- Use resources
    GiveResources = function(self, resources)
        -- TODO: Create Task to make thing, and somehow find a builder and set it off
        -- TODO: Probably need BuilderPools, which can make sure they always have someone free
        return 50 -- TODO: Cost of the thing
        -- TODO: Maybe eventually find a way to refund resources not spent if the build was interrupted
    end,
})

-- Creates a new eco task, and returns it
function NewEcoTask(parent, bpid, priority)
    local task = EcoTask()
    task:New(bpid)
    task.priority = priority
    parent:AddChild(task)
    return task
end