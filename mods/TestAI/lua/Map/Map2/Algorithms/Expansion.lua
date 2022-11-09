
-- Calculates an expansion path
---@class Expansion
Expansion = SimpleClass({


    GetExpansionPath = function(self, source, filterFn, valueFn, threatFn, layer, length)

        -- Need to be able to get candidates that are connected from the relevant layer

        -- First one: air.

        -- Let's use 32x32 for it

        -- Is 64x64 areas appropriate?  That's not a ton of granularity (e.g. to avoid static AA)
        -- 32x32 might actually be better...

    end,

})