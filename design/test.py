import copy
#How to project economy?
#Start with (600, 4000, 1, 20)

# Estimate what the mass curve looks like over time, and the E needed to make stuff?

build_tasks = {}

class Buildable:
    def __init__(self, name, mass, energy, buildtime, buildrate=0, massin=0, energyin=0):
        self.name, self.mass, self.energy, self.buildtime, self.buildrate, self.massin, self.energyin = name, mass, energy, buildtime, buildrate, massin, energyin

# Seraphim
buildables = {
    "acu": Buildable("acu", 99999, 99999, 99999, buildrate=10),  # Omitted m/e in because it's the start anyway
    "landfac1": Buildable("landfac1", 240, 2100, 300, buildrate=20),
    "engy1": Buildable("engy1", 52, 260, 260, buildrate=5),
    "tank1": Buildable("tank1", 54, 270, 270),
    "pgen1": Buildable("pgen1", 75, 750, 125, energyin=20),
    "mex1": Buildable("mex1", 36, 360, 60, buildrate=10, massin=2, energyin=-2),
    "mex2": Buildable("mex2", 900, 5400, 900, buildrate=15, massin=4, energyin=-7),  # Net mass for upgrade
    "hydro": Buildable("hydro", 160, 800, 400, energyin=100),
}

task_id = 1

class BuildTask:
    def __init__(self, name):
        self.unit = buildables[name]
        self.complete_fraction = 0.0
        global task_id
        self.task_id = task_id
        task_id += 1
        self.builders = []  # Builders are never removed partway

    # Returns requested mass and energy to continue this task
    def build_eco_request(self, buildpower):
        if self.complete_fraction > 1.0:
            raise Exception("Already complete", self.unit)
        m_req = self.unit.mass * buildpower / self.unit.buildtime
        e_req = self.unit.energy * buildpower / self.unit.buildtime
        return m_req, e_req
        
    # Continue construction at <fraction> efficiency
    # Returns whether complete and any overflow
    def build_eco_provided(self, buildpower, fraction):
        self.complete_fraction += buildpower / self.unit.buildtime * fraction
        if self.complete_fraction >= 1.0:
            self.builders = []
            return True, self.unit.mass * (self.complete_fraction - 1.0), self.unit.energy * (self.complete_fraction - 1.0)
        return False, 0.0, 0.0


class Builder:
    def __init__(self, unit):
        self.unit = unit  # Buildable
        self.task = None

    def assign_task(self, task):
        if task.complete_fraction > 1.0:
            raise Exception("Already complete", self.unit, task)
        self.task = task
        task.builders.append(self)


class EcoSim:
    def __init__(self, ai):
        self.ai = ai

    def run(self, ticks):
        tick = 0
        mass = 600
        energy = 4000
        mass_in = 1
        energy_in = 20
        m_max = 600
        e_max = 4000

        tick_m_stall_count = 0
        tick_e_stall_count = 0
        tick_m_over_count = -1  # Fudge for having the initial stuff in the wrong order
        tick_e_over_count = -1

        acu = Builder(buildables["acu"])
        self.ai.new_builder(acu)
        self.ai.builder_free(acu)

        builders = [acu]
        tasks = []  # (buildtask, builders)

        while(tick < ticks):
            # Generate economy
            if energy > e_max:
                energy = e_max
                tick_e_over_count += 1
            if mass > m_max:
                mass = m_max
                tick_m_over_count += 1
            energy += energy_in
            mass += mass_in
            print("Tick", tick, "mass", mass, "energy", energy)
            # Not considered: m production and e consumption changing due to e stall hitting mexes

            # Identify tasks and builders
            task_map = {builder.task.task_id: (builder.task, []) for builder in builders if builder.task != None}
            for builder in builders:
                if builder.task != None:
                    task_map[builder.task.task_id][1].append(builder)
            tasks = task_map.values()

            # Produce stuff
            total_m_req = 0
            total_e_req = 0
            for task in tasks:
                bp = sum([b.unit.buildrate for b in task[1]])
                tmr, ter = task[0].build_eco_request(bp)  # Not considered: energy draw from radars and SML and such
                total_m_req += tmr
                total_e_req += ter
            
            fraction = 1.0
            if total_e_req > energy or total_m_req > mass:
                if total_e_req > energy:
                    tick_e_stall_count += 1
                if total_m_req > mass:
                    tick_m_stall_count += 1
                fraction = min(energy / total_e_req, mass / total_m_req)
                if fraction < 0.0:
                    fraction = 0.0

            for task in tasks:
                bp = sum([b.unit.buildrate for b in task[1]])
                done, m_over, e_over = task[0].build_eco_provided(bp, fraction)
                mass += m_over
                energy += e_over
                if (done):
                    print("Finished", task[0].unit.name)
                    unit = task[0].unit
                    mass_in += unit.massin
                    energy_in += unit.energyin
                    if unit.buildrate > 1:
                        b = Builder(task[0].unit)
                        self.ai.new_builder(b)
                        self.ai.builder_free(b)
                        builders += [b]
                    else:
                        self.ai.new_other(task[0].unit)
                    for builder in task[1]:
                        self.ai.builder_free(builder)

            # Spend eco
            mass -= total_m_req * fraction
            energy -= total_e_req * fraction

            # Tick end callback
            self.ai.tick_end(tick, mass, energy, mass_in, energy_in)

            tick += 1
        print("Stalled mass for", tick_m_stall_count, "ticks")
        print("Overflowed mass for", tick_m_over_count, "ticks")
        print("Stalled energy for", tick_e_stall_count, "ticks")
        print("Overflowed energy for", tick_e_over_count, "ticks")


class AI:
    def __init__(self):
        self.builders = []
        self.free_builders = []
        self.tanks = 0
        self.engies = 0
        self.factories = 0
        self.pgens = 0
        self.mexes = 0
        self.hydros = 0

        # Perhaps better to just keep the tasks themselves around and go from that?
        # self.wip_pgens = []  # task; not used because of pgentask
        self.wip_mexes = []  # ^^
        self.wip_engies = []
        # self.wip_factories = []  # not used because of landtask

        # WIP tasks for stuff that gets assisted; always populated
        self.landtask = BuildTask("landfac1")
        self.pgentask = BuildTask("hydro")  # 1 hydro

    # No sophistication in setting the ratio based on needs yet
    def est_demand(self, factories, engies):
        eng_fac_bp = sum([b.unit.buildrate for b in self.builders if b.task != None and b.task.unit.name == "landfac1"])
        demand_m = factories * 4 + (2 + engies) * 3 + eng_fac_bp * 0.2
        demand_e = factories * 20 + (2 + engies) * 30 + 2 * self.mexes + eng_fac_bp  # Future mexes ignored for now
        return demand_m, demand_e

    def est_task_complete_ticks(self, task):
        return 1 + int(task.unit.buildtime * (1.0 - task.complete_fraction) / (0.00001 + sum([b.unit.buildrate for b in task.builders])))

    def project_eco(self, mass, energy, mass_in, energy_in, prediction_ticks):
        # Project when we'll stall and why
        proj_m = mass
        proj_e = energy
        ticks_to_stall = 0
        stall_mass = True
        adj_m_in = 0
        adj_e_in = 0
        while proj_m > mass_in + adj_m_in and proj_e > energy_in + adj_e_in and ticks_to_stall < prediction_ticks:
            ticks_to_stall += 1
            facs = self.factories
            if ticks_to_stall >= self.est_task_complete_ticks(self.landtask):
                facs += 1  # Not projecting beyond this isn't ideal
            engies = self.engies
            for engy in self.wip_engies:
                if ticks_to_stall >= self.est_task_complete_ticks(engy):
                    engies += 1  # Not projecting beyond this isn't ideal

            demand_m, demand_e = self.est_demand(facs, engies)

            proj_m += mass_in - demand_m
            proj_e += energy_in - demand_e
            if ticks_to_stall >= self.est_task_complete_ticks(self.pgentask):
                proj_e += self.pgentask.unit.energyin
                if ticks_to_stall == self.est_task_complete_ticks(self.pgentask):
                    adj_e_in += self.pgentask.unit.energyin
            for mex in self.wip_mexes:
                if ticks_to_stall >= self.est_task_complete_ticks(mex):
                    proj_m += 2
                    proj_e -= 2
                    if ticks_to_stall == self.est_task_complete_ticks(mex):
                        adj_e_in -= 2
                        adj_m_in += 2
                    
        # I think because of the order of eco processing, a stall happens at +income, not +0.
        if proj_e <= energy_in + adj_e_in:
            stall_mass = False
        elif proj_m <= mass_in + adj_m_in:
            stall_mass = True

        return ticks_to_stall, stall_mass

    # Something like this (project stalls), might be good if combined with:
    # Needs pipeline of future mass doing right
    # Maintain a storage buffer proportional to incomes
    # Introduce an overflow compensation system that scales up and down and just fudges the demand calculation if current % is too high.  Grows each tick it's high (esp if trending up), shrinks each tick it's low.
    # Worth including some expected stall compensation so we don't overbuild E during an M stall
    # Projection is important for the initial BO; but after a while only really matters for big users (omni, T3 air etc)
    def tick_end(self, tick, mass, energy, mass_in, energy_in):
        prediction_ticks = 60
        ticks_to_stall, stall_mass = self.project_eco(mass, energy, mass_in, energy_in, prediction_ticks)

        want_engies = 0
        task = None

        free_task_buildpower = sum([b.unit.buildrate for b in self.free_builders if b.unit.name == "acu" or b.unit.name == "engy1"])

        if ticks_to_stall == prediction_ticks:
            # Unfortunately, not stalling doesn't mean we can make a new factory or engy immediately
            print("Not expecting to stall - think about making BP")
            # Prioritize BP
            task = self.landtask

            # Aim for a 1:1 engineer : factory ratio; but let's just always make factories
            if self.factories >= self.engies:
                want_engies = 1  # In some cases might want to make them faster than this; rest of code should support (but probably don't need: it's only a limit on a single tick)
            # Try and recalculate the stall estimate as though we built it; and build eco based on that

            engy_ttb = 6  # Assume it takes this long to make, so adjust eco from there on only
            fac_ttb = 10  # ^^
            ticks_to_stall, stall_mass = self.project_eco(mass + 4 * fac_ttb + 3 * engy_ttb * want_engies, energy + 20 * fac_ttb + 30 * engy_ttb * want_engies, mass_in - 4 - 0.2 * free_task_buildpower, energy_in - 20 - free_task_buildpower, prediction_ticks)
        else:
            print("Expecting to stall M?", stall_mass, "in", ticks_to_stall)

        if ticks_to_stall == prediction_ticks:
            print("Can afford more BP")
            task = self.landtask
        else:
            want_engies = 0
            # Eco
            if stall_mass:
                task = BuildTask("mex1")
            else:
                task = self.pgentask

        taskbp = 0

        for builder in self.free_builders:
            if builder.unit.name == "acu":
                if self.factories < 1:
                    builder.assign_task(self.landtask)  # Definitely need a factory first
                else:
                    builder.assign_task(task)
                    taskbp += 10
            elif builder.unit.name == "landfac1":
                started_engies = self.landfac_free(builder, want_engies)
                want_engies -= started_engies
            if builder.unit.name == "engy1":
                builder.assign_task(task)
                taskbp += 5

        if taskbp > 0 and task.unit.name == "mex1":
            self.wip_mexes.append(task)

        self.free_builders = []  # For now, always give all builders a task

    # Since we haven't included any moving time for engineers, we can't go first engy without stalling; but of course in reality we can because they move a lot
    def landfac_free(self, builder, want_engies):
        if want_engies > 0:  # When we finish a first factory, we predict stall in about 42 ticks
            t = BuildTask("engy1")
            builder.assign_task(t)
            self.wip_engies.append(t)
            return 1
        else:
            builder.assign_task(BuildTask("tank1"))
            return 0

    def builder_free(self, builder):
        self.free_builders.append(builder)

    def new_builder(self, builder):  # Takes a Builder
        self.builders.append(builder)
        if builder.unit.name == "landfac1":
            self.landtask = BuildTask("landfac1")
            self.factories += 1
        elif builder.unit.name == "engy1":
            self.engies += 1
            for u in self.wip_engies:
                if u.complete_fraction > 1.0:
                    self.wip_engies.remove(u)
                    break
        elif builder.unit.name == "mex1":
            self.mexes += 1
            for mex in self.wip_mexes:
                if mex.complete_fraction > 1.0:
                    self.wip_mexes.remove(mex)
                    break

    def new_other(self, other):  # Takes a Buildable
        if other.name == "tank1":
            self.tanks += 1
        elif other.name == "pgen1":
            self.pgentask = BuildTask("pgen1")
            self.pgens += 1
        elif other.name == "hydro":
            self.pgentask = BuildTask("pgen1")  # Only 1 hydro
            self.hydros += 1


def run_test(ticks):
    ai = AI()
    sim = EcoSim(ai)
    sim.run(ticks)
    print("Made", ai.tanks, "tanks", ai.factories, "factories", ai.engies, "engineers", ai.mexes, "mexes", ai.pgens, "pgens", ai.hydros, "hydros")

run_test(300)

# Layout:
# AI: Control stuff
# Builder is a Unit: 
# EcoSim: run the game