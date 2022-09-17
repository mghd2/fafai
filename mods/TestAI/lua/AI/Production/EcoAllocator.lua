-- The Eco[Provider|Allocator|Task] classes handle distributing economy around weighting by priority
-- They form a tree: EcoProvider -> EcoAllocator -> EcoAllocators -> EcoTasks
-- There can be many layers of EcoAllocators

local Task = import('/mods/TestAI/lua/AI/Production/Task.lua')

EcoAllocator = Class({
    New = function(self)
        -- Allocator parameters used by the parent, call UpdateChildParameters on the parent to update these
        -- Must be set on all EcoAllocators or EcoTasks
        self.energy_ratio = 6
        self.minimum_resource_amount = 50
        self.paused = false
        self.priority = 0  -- Must not be negative

        self.parent = nil
        self.children_unpaused = {}  -- Keyed by the child, value is {resource_balance, total_resources_to_funded}
        self.children_paused = {}  -- ^^
        self.total_child_priority = 0

    end,

    -- Add a child EcoAllocator
    AddChild = function(self, child)
        self.children_unpaused[child] = {0, 0}  -- It's always OK to add to unpaused, because it will be moved immediately after
        child.parent = self
        self:UpdateChildParameters()
    end,

    -- Called by a parent to assign a chunk of resources to this allocator
    -- Returns the amount of resources that will be consumed
    GiveResources = function(self, resources)
        if self.total_child_priority <= 0 then
            return 0
        end
        local total_held_resources = 0

        local give_resources = {}

        -- Distribute the resources between children and fund any children that meet their minimum
        -- TODO: Maybe include the paused resources?  Probably not ideal to go super negative
        -- ^^  : Maybe best is to redistribute paused resources beyond the minimum when it pauses?
        for c, v in self.children_unpaused do
            -- Increase child resources
            v[1] = v[1] + resources * (c.priority / self.total_child_priority)

            -- Increase total held resources
            total_held_resources = total_held_resources + v[1]

            if v[1] > c.minimum_resource_amount then
                -- We'll do the actual resource giving later so the children don't get a chance to
                -- re-entrantly change their requests until we've allocated fully.
                give_resources[c] = v[1]
            end

            -- Calculate total additional resources (for us) before this child will be funded
            v[2] = (c.minimum_resource_amount - v[1]) * (self.total_child_priority / (c.priority + 0.00001))
        end

        local function give_child_resources(c, r)
            while r >= c.minimum_resource_amount and not c.paused do
                -- Fund the child and adjust their balance (may go negative)
                -- Get a reference to the table before it maybe pauses re-entrantly
                local child_resources = self.children_unpaused[c]
                local amount_spent = c:GiveResources(r)

                if amount_spent == 0 then
                    break
                end
                r = r - amount_spent
                child_resources[1] = child_resources[1] - amount_spent
                child_resources[2] = (c.minimum_resource_amount - child_resources[1]) * (self.total_child_priority / (c.priority + 0.00001))
            end
        end

        -- Now give out all the resources
        for c, r in give_resources do
            give_child_resources(c, r)
        end

        -- If we have enough resources in total to fund the next thing we'd buy, but not allocated to it yet, fund it now
        -- This prevents the held resources from slowing overall production.
        -- e.g. A has prio 20, B and C prio 10: give 20 resources, A gets 10, B and C get 5, but A is funded (to -10) by borrowing
        while total_held_resources > self.minimum_resource_amount do
            local best_child = nil
            local best_ticks = 9999
            for c, v in self.children_unpaused do
                if v[2] < best_ticks and c.minimum_resource_amount < total_held_resources then
                    -- This child is the closest in time to being funded, and we can afford to fund it now
                    best_child = c
                    best_ticks = v[2]
                end
            end
            if best_child then
                give_child_resources(best_child, total_held_resources)
            else
                -- We often need to break because self.minimum_resource_amount may not be enough to fund the nearest thing
                break
            end
        end
    end,

    -- Notify this EcoAllocator that a child may have changed its parameters
    -- Called whenever a child has been added, removed or updated to recalculate our own parameters
    UpdateChildParameters = function(self)
        -- Unpause the newly unpaused children, and pause the newly paused children
        local now_paused_children = {}
        local now_unpaused_children = {}
        for c, v in self.children_paused do
            if c.paused then
                now_paused_children[c] = v
            else
                now_unpaused_children[c] = v
            end
        end
        for c, v in self.children_unpaused do
            if c.paused then
                now_paused_children[c] = v
            else
                now_unpaused_children[c] = v
            end
        end
        self.children_paused = now_paused_children
        self.children_unpaused = now_unpaused_children

        -- Recalculate our energy_ratio, minimum_resource_amount and total_child_priority
        self.minimum_resource_amount = 999999
        self.total_child_priority = 0
        local weighted_e_ratio = 0
        for _, c in self.children_unpaused do
            if c.minimum_resource_amount < self.minimum_resource_amount then
                self.minimum_resource_amount = c.minimum_resource_amount
            end
            weighted_e_ratio = weighted_e_ratio + c.priority * c.energy_ratio
            self.total_child_priority = self.total_child_priority + c.priority
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

    end,

    -- Use resources
    GiveResources = function(self, resources)
        -- TODO: Create Task to make thing, and somehow find a builder and set it off
        -- TODO: Probably need BuilderPools, which can make sure they always have someone free
        return 70 -- TODO: Cost of the thing
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