# CondaPkg.jl

Add [Conda](https://docs.conda.io/en/latest/) dependencies to your Julia project.

You declare Conda dependencies in a `CondaPkg.toml` file, and CondaPkg will install those
dependencies into a Conda environment. This environment is specific to the current Julia
project, so there are no cross-project version conflicts.

## Install

```
pkg> add CondaPkg
```

## Usage

### CondaPkg.toml

To specify Conda dependencies, create a file called `CondaPkg.toml` in your Julia
project.

For example:
```toml
[deps]
python = ">=3.5,<4"
perl = ">=5,<6"
```

The next time dependencies are resolved, a Conda environment specific to your current Julia
project is created with these dependencies.

Dependencies from `CondaPkg.toml` files in any packages installed in the current project are
also included. This means that package authors can write a `CondaPkg.toml` file and
dependencies should just work.

### Specify dependencies interactively

Instead of modifying `CondaPkg.toml` by hand, you can use these convenience functions.

- `status()` shows the Conda dependencies of the current project.
- `add(deps...)` adds/replaces dependencies (package names, `name => spec` pairs, or iterables of these).
- `rm(deps...)` removes dependencies (package names or iterables of these).

### Access the Conda environment

- `envdir()` returns the root directory of the Conda environment.
- `withenv(f)` returns `f()` evaluated in the Conda environment.
- `which(progname)` find the program in the Conda environment.
- `resolve(; force=false)` resolves dependencies. You don't normally need to call this
  because the other API functions will automatically resolve first. Pass `force=true` if
  you change a `CondaPkg.toml` file mid-session.

### Examples

Assuming one of the dependencies in `CondaPkg.toml` is `python` then the following runs
Python to print its version.
```julia
# Simplest version.
CondaPkg.withenv() do
  run(`python --version`)
end
# Guaranteed not to use Python from outside the Conda environment.
CondaPkg.withenv() do
  python = CondaPkg.which("python")
  run(`$python --version`)
end
# Explicitly specifies the path to the executable (this is package-dependent).
CondaPkg.withenv() do
  python = joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
  run(`$python --version`)
end
```
