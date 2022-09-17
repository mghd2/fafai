local lust = require "fa/tests/lust"
require "tests/init_faf.lua"

local eco = import('mods/TestAI/lua/AI/Production/EcoAllocator.lua')

lust.describe("Test Eco Allocator", function()
    lust.describe("string", function()
        lust.it("StringSplit empty", function()
            lust.expect(StringSplit("")).to.equal({})
        end)
    end)
end)

lust.finish()
