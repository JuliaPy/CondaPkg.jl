# Only run the gc tests on CI (because it's annoying to do it locally)
const testgc = get(ENV, "CI", "") == "true"

# output more than usual when testing
ENV["JULIA_CONDAPKG_VERBOSITY"] = "0"

status() = sprint(io -> CondaPkg.status(io = io))

const backend = get(ENV, "JULIA_CONDAPKG_BACKEND", "MicroMamba")

const isnull = backend == "Null"
const ispixi = backend == "SystemPixi"

# reset the package state (so tests are independent of the order they are run)
rm(CondaPkg.cur_deps_file(), force = true)
CondaPkg.STATE.backend = :NotSet
CondaPkg.STATE.condaexe = ""
CondaPkg.STATE.pixiexe = ""
CondaPkg.STATE.resolved = false
CondaPkg.STATE.load_path = String[]
CondaPkg.STATE.meta_dir = ""
CondaPkg.STATE.frozen = false
CondaPkg.STATE.conda_env = ""
CondaPkg.STATE.shared = false

ENV["JULIA_DEBUG"] = "CondaPkg"
