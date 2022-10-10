import random
from tkinter import E
import matplotlib.pyplot as pyplot

# Eco test harness the second

class Buildable:
    def __init__(self, name, mass, energy, buildtime, buildrate=0, massin=0, energyin=0):
        self.name, self.mass, self.energy, self.buildtime, self.buildrate, self.massin, self.energyin = name, mass, energy, buildtime, buildrate, massin, energyin

    # Returns the ongoing mass, energy impact of building this (and using its buildpower)
    # e.g. mex = +2 mass/s, -2 energy/s; factory is -4 mass, -20 energy
    def ongoing_impact(self):
        if self.name == "landfac1":
            # Doing this one separately because BP:mass:energy for mobile units is different
            return -4, -20
        elif self.name[:3] == "mex":
            # Omit buildpower: we're not going to upgrade immediately
            # TODO: Figure out how to represent mex upgrades
            # The cost of upgrade and BP of the T1 mex need to be accounted for then
            # But not continuously reserved like other buildpower
            return self.massin, self.energyin
        else:
            # TODO: More sophisticated average consumption
            # It's probably appropriate for this to be biased towards the needs
            # of making mexes and pgens; because if we're worried about stalling they're what we make
            return self.massin - self.buildrate * 0.7, self.energyin - self.buildrate * 6.25

            # ACU making facs is 8, 70
            # pgens is 6, 60
            # mexes is 6, 60

buildables = {
    "acu": Buildable("acu", 99999, 99999, 99999, buildrate=10, massin=1, energyin=20),  # Omitted m/e in because it's the start anyway
    "landfac1": Buildable("landfac1", 240, 2100, 300, buildrate=20),
    "engy1": Buildable("engy1", 52, 260, 260, buildrate=5),
    "tank1": Buildable("tank1", 54, 270, 270),
    "pgen1": Buildable("pgen1", 75, 750, 125, energyin=20),
    "mex1": Buildable("mex1", 36, 360, 60, buildrate=10, massin=2, energyin=-2),
    "mex2": Buildable("mex2", 900, 5400, 900, buildrate=15, massin=4, energyin=-7),  # Net mass for upgrade
    "hydro": Buildable("hydro", 160, 800, 400, energyin=100),
    "nothing": Buildable("nothing", 0.1, 0.1, 100),
}


class BuildTask:
    def __init__(self, what, builders) -> None:
        self.what = buildables[what]
        self.builders = builders
        self.buildpower = sum([b.buildrate for b in builders])
        self.progress = 0.0

    # TODO: Need to return excess resources too
    def build(self, rate_fraction):
        # TODO: Check the *10 is right
        self.progress += (self.buildpower * rate_fraction / (self.what.buildtime * 10))
        return (self.progress > 0.99999)

    # ETA assuming rate_fraction == 1.0
    # In seconds
    def eta(self):
        return int((self.what.buildtime / self.buildpower) * (1 - self.progress))
        

class AI:
    def __init__(self) -> None:
        pass

    def tick(self, idle_builders, sim):
        tasks = []
        for b in idle_builders:
            if b.name == "landfac1":
                tasks.append(BuildTask("engy1", [b]))
            elif b.name == "acu":
                if random.randint(0, 100) < 40:
                    tasks.append(BuildTask("mex1", [b]))
                else:
                    tasks.append(BuildTask("pgen1", [b]))
            elif b.name == "engy1":
                    tasks.append(BuildTask("mex1", [b]))
            else:
                pass
        return tasks

    def test(self, test_ticks):
        sim = GameSim()
        sim.RunAI(self, test_ticks)
        return sim


# Predict stalls and try to avoid them
class StallForecaster(AI):
    def __init__(self) -> None:
        super().__init__()

    def tick(self, idle_builders, sim):
        #if len(idle_builders) == 0:
        #    return []
        tasks = []
        m, e = self.predict_eco(sim)
        #print(sim.tick, "Stalling in", m, e)
        for b in idle_builders:
            if b.name == "landfac1":
                # Recalculate with an extra engy
                task = BuildTask("engy1", [b])
                m, e = self.predict_eco(sim, tasks + [task])
                if e > 80 and m > 60:  # This is too cautious probably
                    # These numbers ^^ vs the factory number below need to be similar
                    # or one of them will be overprioritized
                    print(sim.tick, "Making engy")
                    tasks.append(task)
                else:
                    print(sim.tick, "Making tank")
                    tasks.append(BuildTask("tank1", [b]))
            elif b.name[:3] == "mex":
                # No mex upgrades for now
                pass
            else:
                # Maybe I could weight the times based on repayment time?
                if 1.5 * m > e and e < 100:
                    print(sim.tick, b.name, "Making pgen")
                    tasks.append(BuildTask("pgen1", [b]))
                elif m < 100:
                    print(sim.tick, b.name, "Making mex")
                    # Probably fine to not repredict with the -2 extra E
                    tasks.append(BuildTask("mex1", [b]))
                else:
                    # Recalculate with an extra factory
                    task = BuildTask("landfac1", [b])
                    m, e = self.predict_eco(sim, tasks + [task])
                    if m > 80 and e > 80:  # These numbers must be shorter than the limits above
                        print(sim.tick, b.name, "Making factory")
                        tasks.append(task)
                    else:
                        tasks.append(BuildTask("nothing", [b]))
        
        m, e = self.predict_eco(sim, tasks)
        #print(sim.tick, "After builds stalling in", m, e)
        #print(sim.tick, "Current is", sim.mass, sim.energy)
        built_counts = {k: len(v) for k, v in sim.built_ticks.items()}
        #print(sim.tick, "Have ", built_counts)
        return tasks


    # Does predictive eco even work?
    # ACU is +1, +10
    # Let's say a factory costs 100, 1000 (-2, -10)
    # A mex or engy costs 10, 100 (gives +1), and a pgen 40, 400 (gives +10)
    # Everything builds in 10 ticks
    # Start with 200, 2000
    # Factory done at say 120, 2400
    # M stall in 120 and E in 9999; no problem
    # ACU needs to fund itself is the problem

    # Returns seconds to stalling mass, energy
    def predict_eco(self, sim, extra_tasks=[]):
        # Fund the existing units
        # TODO: Use current real trend as the initial net instead; and only theoretical numbers
        # for delta?  Need to check appearance of team overflow in metrics
        mass_net = 0.0  # Per second
        energy_net = 0.0
        for k, v in sim.built_ticks.items():
            thing = buildables[k]
            m, e = thing.ongoing_impact()
            mass_net += len(v) * m
            energy_net += len(v) * e

        # Work out when we think our tasks will complete
        # This will be wrong if we actually stall
        changes = []  # Each is (eta, mass_delta_after_eta, energy_delta_after_eta)
        for t in sim.tasks + extra_tasks:
            eta = t.eta()
            m, e = t.what.ongoing_impact()
            changes.append((eta, m, e))

        # Identify when we'll stall
        mass_stall_time = 9999
        energy_stall_time = 9999
        mass = sim.mass
        energy = sim.energy
        change_m_so_far = 0.0
        change_e_so_far = 0.0
        for t in range(0, 150):
            # Existing structures
            mass += mass_net + change_m_so_far
            energy += energy_net + change_e_so_far
            mass = min(600, mass)
            energy = min(4000, energy)

            # New structures
            while len(changes) > 0 and t >= changes[0][0]:
                change_m_so_far += changes[0][1]
                change_e_so_far += changes[0][2]
                changes.pop(0)

            if mass_stall_time > 1000 and mass < 0:
                mass_stall_time = t
            if energy_stall_time > 1000 and energy < 0:
                energy_stall_time = t

        #print("For prediction; final incomes are", mass_net, change_m_so_far, energy_net, change_e_so_far)
        return mass_stall_time, energy_stall_time


# Try and calculate amounts of things and build to that number
class CalculatedEco(AI):
    def __init__(self) -> None:
        super().__init__()

    def tick(self, idle_builders, sim):
        # Include WIP structures in counts
        pgens_total = len(sim.built_ticks["pgen1"]) + len([t for t in sim.tasks if t.what.name == "pgen1"])
        mexes_total = len(sim.built_ticks["mex1"]) + len([t for t in sim.tasks if t.what.name == "mex1"])
        facs_total = len(sim.built_ticks["landfac1"]) + len([t for t in sim.tasks if t.what.name == "landfac1"])
        engies_total = len(sim.built_ticks["engy1"]) + len([t for t in sim.tasks if t.what.name == "engy1"])

        pgens_need = facs_total + engies_total * 1.5
        mexes_need = facs_total * 2 + engies_total * 2
        facs_need = mexes_total * 0.4  # 80% of mass to facs
        engies_need = mexes_total * 0.2 # 20% to engies

        # First make enough pgens
        if pgens_total < pgens_need:
            pass
        # Then enough mexes
        # Then enough factories
        # Then more engies


# Helper AI for RecursiveSim, that runs a set BO and then idles
class SubAI(AI):
    def __init__(self, bo) -> None:
        super().__init__()
        self.bo = bo

    def tick(self, idle_builders, sim):
        tasks = []
        for b in idle_builders:
            t = "nothing"
            if len(self.bo) > 0:
                t = self.bo.pop()
            tasks.append(BuildTask(t, [b]))
        return tasks


# Recursively re-run the simulation as prediction
class RecursiveSim(AI):
    def __init__(self) -> None:
        super().__init__()
        self.bo = []  # The name of the thing to build

    def tick(self, idle_builders, sim):
        tasks = []
        for b in idle_builders:
            best_score = -99999
            best_task = "nothing"
            for x in buildables.keys():  # TODO: Need to police for can b build x
                subai = SubAI(self.bo + [x])
                subsim = subai.test(900)
                score = self.score(subsim)
                if score > best_score:
                    best_score = score
                    best_task = x
            self.bo.append(best_task)
            tasks.append(BuildTask(best_task, [b]))

        return tasks

    def score(self, sim):
        return 800 * sim.mass_in + 100 * sim.energy_in + sim.total_m_spend
        # Pretty good with a fairly long subsim
        # return sim.total_m_spend + 1200 * sim.commit_total - sim.e_stall_ticks


# TODO: Probably good enough to run the simulation with a 10 tick granularity
class GameSim:
    def __init__(self):
        self.tick = 1
        self.mass = 600
        self.energy = 4000
        self.mass_in = 1  # These numbers are per second
        self.energy_in = 20
        self.mass_req = 0
        self.energy_req = 0
        self.tasks = []
        self.e_stall_ticks = 0
        self.commit_total = 1.0
        self.m_overflow_total = 0
        self.total_m_spend = 0
        self.total_e_spend = 0
        self.built_ticks = {}
        self.mass_hist = []
        self.energy_hist = []

    def run_tick(self):
        self.mass_hist.append(self.mass)
        self.energy_hist.append(self.energy)

        # Generate economy
        self.tick += 1  
        self.mass += self.mass_in / 10  # TODO: Stall mexes
        self.energy += self.energy_in / 10
        if self.mass > 600:
            self.m_overflow_total += (self.mass - 600)
            self.mass = min(self.mass, 600)
        self.energy = min(self.energy, 4000)

        # Work out requests
        self.mass_req = 0.0
        self.energy_req = 0.0
        for t in self.tasks:
            self.mass_req += t.what.mass * (t.buildpower / t.what.buildtime)
            self.energy_req += t.what.energy * (t.buildpower / t.what.buildtime)

        # Work out fulfilment percentage
        fulfil = 1.0
        m_limit = 0.0
        if self.mass_req / 10 > self.mass:
            m_limit = self.mass / (self.mass_req / 10 + 0.0000001)
            fulfil = min(fulfil, m_limit)
        if self.energy_req / 10 > self.energy:
            e_limit = self.energy / (self.energy_req / 10 + 0.0000001)

            fulfil = min(fulfil, e_limit)
            if e_limit < 0.999:
                self.e_stall_ticks += 1
        self.total_m_spend += self.mass_req / 10 * fulfil
        self.total_e_spend += self.energy_req / 10 * fulfil
        self.mass -= self.mass_req / 10 * fulfil
        self.energy -= self.energy_req / 10 * fulfil
        self.commit_total += fulfil
        #if self.tick % 10 == 0:
        #    print("Tick", self.tick, "- fulfilling", int(100 * fulfil), "%, Mass=", self.mass,"Energy=", self.energy)

        completed_builders = []
        still_wip = []
        for t in self.tasks:
            if t.build(fulfil):
                #print("Finished building:", t.what.name)
                completed_builders += t.builders
                if t.what.buildrate > 0:
                    completed_builders.append(t.what)
                self.mass_in += t.what.massin
                self.energy_in += t.what.energyin
                if t.what.name in self.built_ticks:
                    self.built_ticks[t.what.name].append(self.tick)
                else:
                    self.built_ticks[t.what.name] = [self.tick]
            else:
                still_wip.append(t)
        self.tasks = still_wip

        return completed_builders

    # score_built calculates the time weighted value of all the things we've built
    def score_built(self):
        # TODO: Actually look at what we built
        return self.total_m_spend

    def plot_resources(self):
        pyplot.plot(self.mass_hist, label="Mass")
        pyplot.plot(self.energy_hist, label="Energy")
        pyplot.legend()

    def add_tasks(self, tasks):
        self.tasks += tasks
        
    def RunAI(self, ai, test_ticks):
        # Initial factory
        acu = buildables["acu"]
        self.built_ticks["acu"] = [1]
        fac1 = BuildTask("landfac1", [acu])
        self.add_tasks([fac1])

        for _ in range(1, test_ticks):
            idle_builders = self.run_tick()
            tasks = ai.tick(idle_builders, self)
            self.add_tasks(tasks)


def Test():
    test_ticks = 6000  # 10 minutes
    sim = GameSim()
    ai = AI()
    sim.RunAI(ai, test_ticks)

    print("Stalled energy for", sim.e_stall_ticks)
    print("Overflowed", sim.m_overflow_total, "mass")
    print("Buildpower utilization (considering stalls)", int(100*(sim.commit_total / test_ticks)), "%")
    print("Total spend:", sim.total_m_spend, "mass", sim.total_e_spend, "energy")
    build_totals = {k:len(v) for (k, v) in sim.built_ticks.items()}
    print("Built:", build_totals)