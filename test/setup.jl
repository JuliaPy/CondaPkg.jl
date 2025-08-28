# Only run the gc tests on CI (because it's annoying to do it locally)
const testgc = get(ENV, "CI", "") == "true"

status() = sprint(io -> CondaPkg.status(io = io))

const backend = get(ENV, "JULIA_CONDAPKG_BACKEND", "Pixi")

const isnull = backend == "Null"
const ispixi = backend == "SystemPixi" || backend == "Pixi"

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
CondaPkg.STATE.testing = true
CondaPkg.STATE.test_preferences = Dict{String,Any}("backend" => backend)

# link the test folder into the test environment, e.g. for accessing test data
let test_dir = joinpath(dirname(CondaPkg.cur_deps_file()), "test")
    if !ispath(test_dir)
        symlink(joinpath(dirname(dirname(pathof(CondaPkg))), "test"), test_dir)
    end
end

ENV["JULIA_DEBUG"] = "CondaPkg"
