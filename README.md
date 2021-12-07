# CondaPkg.jl

Add Conda dependencies to your Julia environment.

You declare Conda dependencies in a `CondaPkg.toml` file, and CondaPkg will install those
dependencies into a Conda environment. This environment is specific to the current Julia
project, so there are not cross-project version conflicts.

## Install

```
pkg> add CondaPkg
```

## Usage

### CondaPkg.toml

To specify Conda dependencies, create a file called `CondaPkg.toml` in your Julia
project/environment/package.

For example:
```toml
[deps]
python = ">=3.5,<4"
perl = ">=5,<6"
```

The next time dependencies are resolved, a Conda environment specific to your current Julia
project is created with these dependencies.

Dependencies from `CondaPkg.toml` files in any packages installed in the current environment
are also included. This means that package authors can write a `CondaPkg.toml` file and
dependencies should just work.

### API

- `resolve(; force=false)` resolves dependencies. You don't normally need to call this
  because all other API functions will automatically resolve first. Pass `force=true` if
  you change a `CondaPkg.toml` file mid-session.
- `env()` returns the path to the Conda environment.
- `withenv(f)` returns `f(env())` evaluated in the Conda environment.

### Examples

Assuming one of the dependencies in `CondaPkg.toml` is `python` then the following runs
Python to print its version.
```julia
CondaPkg.withenv(env -> run(`python --version`))
```

If you wish to be more explicit, you can use the `env` argument. For example on Windows
you can do:
```julia
CondaPkg.withenv(env -> run(`$env/python.exe --version`))
```
