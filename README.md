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

### API

- `resolve(; force=false)` resolves dependencies. You don't normally need to call this
  because the other API functions will automatically resolve first. Pass `force=true` if
  you change a `CondaPkg.toml` file mid-session.
- `withenv(f)` returns `f()` evaluated in the Conda environment.
- `envdir()` returns the root directory of the Conda environment.
- `bindir()` returns the binary directory of the Conda environment.
- `scriptdir()` returns the script directory of the Conda environment.
- `libdir()` returns the library directory of the Conda environment.
- `pythonpath()` returns the path of the Python executable in the Conda environment.

### Examples

Assuming one of the dependencies in `CondaPkg.toml` is `python` then the following runs
Python to print its version.
```julia
CondaPkg.withenv(); do run(`$(CondaPkg.pythonpath()) --version`); end
```

Similarly, the following will run Perl, assuming `perl` is a dependency:
```julia
CondaPkg.withenv(); do run(`$(CondaPkg.bindir("perl"))) --version`); end
```
