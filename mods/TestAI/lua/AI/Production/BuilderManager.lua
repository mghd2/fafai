-- Maintains the available builders (engineers and factories), providing them for tasks and requesting more production as needed
BuilderManager = Class({
    GetBuilder = function(self, bpid)

    end,

    GetEngineer = function(self, tech)
    end,

    GetFactory = function(self, tech, layer)
    end,
})

-- How to handle builders?
-- Already have a builder manager that watches for idle builders; it could maintain a list
-- And when we fund a Task then pull from the list?  Good for assistance