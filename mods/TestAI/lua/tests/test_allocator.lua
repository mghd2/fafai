local lust = import("/mods/TestAI/lua/tests/lust.lua").Lust()

local EA = import("/mods/TestAI/lua/AI/Production/EcoAllocator.lua")

local function initAllocs()
    local ea1 = EA.EcoAllocator()
    ea1:New(100)
    local ep = EA.EcoProvider()
    ep:New(ea1)
    return ep, ea1
end

TestTask = Class({
    New = function(self, parent, priority, minimum, consume)
        LOG("PRIO "..repr(priority))
        self.energy_ratio = 6
        self.minimum_resource_amount = minimum
        self.consume_amount = consume
        self.paused = false
        self.priority = priority  -- Must not be negative
        self.funded_count = 0
        parent:AddChild(self)
    end,

    GiveResources = function(self, resources)
        lust.expect(resources).to.exceed(self.minimum_resource_amount - 0.1)
        self.funded_count = self.funded_count + 1
        return self.consume_amount
    end,

    CalculateEffectiveMinimum = function(self)
        return self.minimum_resource_amount
    end,

    FundCountSinceLastCheck = function(self)
        local fc = self.funded_count
        self.funded_count = 0
        return fc
    end,
})

function MakeTestTask(...)
    local tt = TestTask()
    tt:New(unpack(arg))
    return tt
end

function Run()
    lust.describe("simple direct EcoAllocation to a single task", function()
        local ep, ea1 = initAllocs()
        local et1 = MakeTestTask(ea1, 100, 50, 50)
        lust.it("builds the task when funded in one go", function()
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(0)
            ep:GiveResources(50)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(1)
        end)
        lust.it("builds the task again when funded in one go", function()
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(0)
            ep:GiveResources(50)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(1)
        end)
        lust.it("builds the task again when funded in two goes", function()
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(0)
            ep:GiveResources(30)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(0)
            ep:GiveResources(20)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(1)
        end)
        lust.it("builds the task twice when funded heavily", function()
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(0)
            ep:GiveResources(100)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(2)
        end)
        lust.it("builds and carries forwards extra", function()
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(0)
            ep:GiveResources(75)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(1)
            ep:GiveResources(75)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(2)
        end)
    end)

    lust.describe("simple direct EcoAllocation to multiple tasks", function()
        local ep, ea1 = initAllocs()
        local et1 = MakeTestTask(ea1, 100, 49, 49)  -- 40% allocation
        local et2 = MakeTestTask(ea1, 50, 50, 50)  -- 20% allocation
        local et3 = MakeTestTask(ea1, 100, 149, 149)  -- 40% allocation
        local function checkAll(c1, c2, c3)
            lust.expect(et1:FundCountSinceLastCheck()).to.equal(c1)
            lust.expect(et2:FundCountSinceLastCheck()).to.equal(c2)
            lust.expect(et3:FundCountSinceLastCheck()).to.equal(c3)
        end

        -- Numbers in comments are approximate - I tweaked things by a little to make it more deterministic
        lust.it("builds the highest cost / priority task first, with borrowing", function()
            checkAll(0, 0, 0)
            ep:GiveResources(50)  -- (20=1.5away, 10=4away, 20=6.5away) before borrowing
            checkAll(1, 0, 0)  -- (-29, 10, 20) after borrowing
        end)
        lust.it("builds the task again with more debt", function()
            ep:GiveResources(50)  -- (-9=2.9away, 20=3away, 40=5.5away) before borrowing
            checkAll(1, 0, 0)  -- (-58, 20, 40)
        end)
        lust.it("switches to a lower priority task occasionally", function()
            ep:GiveResources(50)  -- (-38=4.5away, 30=2away, 60=4.5away)
            checkAll(0, 1, 0)  -- (-38, -20, 60)
        end)
        lust.it("only builds high priority expensive tasks after a waiting to afford them", function()
            ep:GiveResources(50)  -- (-18=3.5away, -10=6away, 80=3.5away)
            checkAll(1, 0, 0)  -- (-67, -10, 80)
            ep:GiveResources(50)  -- (-47=5away, 0=5away, 100=2.5away)
            checkAll(0, 0, 0)  -- Closest is too expensive still
            ep:GiveResources(50)  -- (-27=4away, 10=4away, 120=1.5away)
            checkAll(0, 0, 0)  -- Closest is too expensive still
            ep:GiveResources(50)  -- (-7=3away, 20=3away, 140=0.5away)
            checkAll(0, 0, 1)  -- Now we can afford to borrow for it
        end)
        lust.it("uses the right ratios in the long run", function()
            for _ = 1, 10 do
                ep:GiveResources(100000)
            end
            -- All must be within 5 of the long term split
            local et1c, et2c, et3c = et1:FundCountSinceLastCheck(), et2:FundCountSinceLastCheck(), et3:FundCountSinceLastCheck()
            lust.expect(et1c).to.exceed(8158)
            lust.expect(et1c).to_not.exceed(8169)
            lust.expect(et2c).to.exceed(3995)
            lust.expect(et2c).to_not.exceed(4005)
            lust.expect(et3c).to.exceed(2679)
            lust.expect(et3c).to_not.exceed(2690)
        end)
    end)

    lust.describe("distribution between multiple allocators", function()
        local ep, ea1 = initAllocs()  -- Each allocator is numbered so that their parent is them[:-1]

        -- Equal split at this layer
        local ea11 = EA.EcoAllocator()
        ea11:New(100)
        ea1:AddChild(ea11)
        local ea12 = EA.EcoAllocator()
        ea12:New(100)
        ea1:AddChild(ea12)

        -- 90:10 at this layer
        local ea121 = EA.EcoAllocator()
        ea121:New(90)
        ea12:AddChild(ea121)
        local ea122 = EA.EcoAllocator()
        ea122:New(10)
        ea12:AddChild(ea122)

        -- Each leaf allocator only has one child, so the priorities shouldn't matter
        local et11 = MakeTestTask(ea11, 5, 50, 50)  -- Should receive 50% = 50%
        local et121 = MakeTestTask(ea121, 100, 500, 500)  -- Should receive 45% = 50% * 90%
        local et122 = MakeTestTask(ea122, 10000, 50, 50)  -- Should receive 5% = 50% * 10%

        local function checkAll(c1, c2, c3)
            local et11c, et121c, et122c = et11:FundCountSinceLastCheck(), et121:FundCountSinceLastCheck(), et122:FundCountSinceLastCheck()
            LOG("Got "..et11c..", "..et121c..", "..et122c)
            lust.expect(et11c).to.equal(c1)
            lust.expect(et121c).to.equal(c2)
            lust.expect(et122c).to.equal(c3)
        end

        lust.it("builds the highest cost / priority task first, with borrowing", function()
            checkAll(0, 0, 0)
            ep:GiveResources(50)  -- (25, 22.5, 2.5) before borrowing
            checkAll(1, 0, 0)  -- (-25, 22.5, 2.5) after borrowing
        end)
        lust.it("builds the task again with more debt", function()
            LOG("EA11"..repr(ea11))  -- 0; needs 50
            LOG("EA12"..repr(ea12))  -- showing 0, 0; needs 0, 0????
            LOG("EA121"..repr(ea121))  -- Also 0s
            LOG("EA122"..repr(ea122))
            ep:GiveResources(50)  -- (0=2away, 45=lotsaway, 5=9away) before borrowing
            checkAll(1, 0, 0)  -- (-50, 45=20.2away, 5=18away)
            -- FAIL: seeing 0, 0, 1

            -- TODO: I think I should just make it single level
            -- Too much weirdness otherwise
        end)
        lust.it("switches between allocators and builds multiple at once", function()
            ep:GiveResources(1000)  -- (450, 500, 55)
            checkAll(9, 1, 1)  -- (-50, 450, 0)
            -- The exact sequence here is a bit complex; because there's tiers of borrowing
        end)
        lust.it("uses the right ratios in the long run", function()
            for _ = 1, 10 do
                ep:GiveResources(100000)
            end
            -- All must be within 5 of the long term split
            local et11c, et121c, et122c = et11:FundCountSinceLastCheck(), et121:FundCountSinceLastCheck(), et122:FundCountSinceLastCheck()
            lust.expect(et11c).to.exceed(9995)
            lust.expect(et11c).to_not.exceed(10005)
            lust.expect(et121c).to.exceed(895)
            lust.expect(et121c).to_not.exceed(905)
            lust.expect(et122c).to.exceed(995)
            lust.expect(et122c).to_not.exceed(1005)
        end)
    end)

    -- TODO: updating parameters

    lust.finish()
end
