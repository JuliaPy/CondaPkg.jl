<img src="https://github.com/JuliaPy/CondaPkg.jl/raw/main/logo.png" alt="CondaPkg.jl logo" style="width: 100px;">

# CondaPkg.jl

[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Test Status](https://github.com/JuliaPy/CondaPkg.jl/actions/workflows/tests.yml/badge.svg)](https://github.com/JuliaPy/CondaPkg.jl/actions/workflows/tests.yml)
[![Codecov](https://codecov.io/gh/JuliaPy/CondaPkg.jl/branch/main/graph/badge.svg?token=1flP5128hZ)](https://codecov.io/gh/JuliaPy/CondaPkg.jl)

Add [Conda](https://docs.conda.io/en/latest/) dependencies to your Julia project.

## Overview

This package is a lot like Pkg from the Julia standard library, except that it is for
managing Conda packages.
- Conda dependencies are defined in `CondaPkg.toml`, which is analogous to `Project.toml`.
- CondaPkg will install these dependencies into a Conda environment specific to the current
  Julia project. Hence dependencies are isolated from other projects or environments.
- Functions like `add`, `rm`, `status` exist to edit the dependencies programmatically.
- Or you can do `pkg> conda add some_package` to edit the dependencies from the Pkg REPL.

## Install

```
pkg> add CondaPkg
```

## Specifying dependencies

### Pkg REPL

The simplest way to specify Conda dependencies is through the Pkg REPL, just like for Julia
dependencies. For example:
```
julia> using CondaPkg
julia> # now press ] to enter the Pkg REPL
pkg> conda status                # see what we have installed
pkg> conda add python perl       # adds conda packages
pkg> conda pip_add build         # adds pip packages
pkg> conda rm perl               # removes conda packages
pkg> conda run python --version  # runs the given command in the conda environment
pkg> conda update                # update conda and pip installed packages
```

For more information do `?` or `?conda` from the Pkg REPL.

**Note:** We recommend against adding Pip packages unless necessary - if there is a
corresponding Conda package then use that. Pip does not handle version conflicts
gracefully, so it is possible to get incompatible versions.

### Functions

These functions are intended to be used interactively when the Pkg REPL is not available
(e.g. if you are in a notebook):

- `status()` shows the Conda dependencies of the current project.
- `add(pkg; version="", channel="")` adds/replaces a dependency.
- `rm(pkg)` removes a dependency.
- `add_channel(channel)` adds a channel.
- `rm_channel(channel)` removes a channel.
- `add_pip(pkg; version="")` adds/replaces a pip dependency.
- `rm_pip(pkg)` removes a pip dependency.

### CondaPkg.toml

Finally, you may edit the `CondaPkg.toml` file directly. Here is a complete example:
```toml
channels = ["anaconda", "conda-forge"]

[deps]
# Conda package names and versions
python = ">=3.5,<4"
pyarrow = "==6.0.0"
perl = ""

[deps.llvmlite]
# Long syntax to specify other fields, such as the channel and build
version = ">=0.38,<0.39"
channel = "numba"
build = "*"

[pip.deps]
# Pip package names and versions
build = "~=0.7.0"
six = ""
some-remote-package = "@ https://example.com/foo.zip"
some-local-package = "@ ./foo.zip"

[pip.deps.nmslib]
# Long syntax to specify other fields
version = "~=2.1"
binary = "no"  # or "only"
```

## Access the Conda environment

- `envdir()` returns the root directory of the Conda environment.
- `withenv(f)` returns `f()` evaluated in the Conda environment.
- `which(progname)` find the program in the Conda environment.
- `resolve(; force=false)` resolves dependencies. You don't normally need to call this
  because the other API functions will automatically resolve first. Pass `force=true` if
  you change a `CondaPkg.toml` file mid-session.
- `update()` update the conda and pip installed packages.
- `gc()` removes unused caches to save disk space.

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

## Details

### Conda channels

You can specify the channel to install a particular package from, such as with
`pkg> conda add some-channel::some-package`.

You can also specify a top-level list of channels, from which all other packages are
installed, such as with `pkg> conda channel_add some-channel`.

By default, packages are installed from the `conda-forge` channel.

### Pip packages

Direct references such as `foo@http://example.com/foo.zip` are allowed. As a special case
if the URL starts with `.` then it is interpreted as a path relative to the directory
containing the `CondaPkg.toml` file.

Additionally the binary mode specifies whether to only use binary distributions ("only") or
to never use them ("no").

### Preferences

You can configure this package with a number of preferences. These can be set either as
[Julia preferences](https://github.com/JuliaPackaging/Preferences.jl) or as environment
variables. This table gives an overview of the preferences, and later sections describe them
in more detail.

| Preference | Environment variable | Description |
| ---------- | -------------------- | ----------- |
| `backend` | `JULIA_CONDAPKG_BACKEND` | One of `MicroMamba`, `System`, `Current` or `Null` |
| `exe` | `JULIA_CONDAPKG_EXE` | Path to the Conda executable. |
| `offline` | `JULIA_CONDAPKG_OFFLINE` | When `true`, work in offline mode. |
| `env` | `JULIA_CONDAPKG_ENV` | Path to the Conda environment to use. |
| `verbosity` | `JULIA_CONDAPKG_VERBOSITY` | One of `-1`, `0`, `1` or `2`. |

The easiest way to set these preferences is with the
[`PreferenceTools`](https://github.com/cjdoris/PreferenceTools.jl)
package. For example:
```
julia> using PreferenceTools
julia> # now press ] to enter the Pkg REPL
pkg> preference add CondaPkg backend=System offline=true
```

### Backends

This package has a number of different "backends" which control exactly which implementation
of Conda is used to manage the Conda environments. You can explicitly select a backend
by setting the `backend` preference to one of the following values:
- `MicroMamba`: Uses MicroMamba from the package
  [MicroMamba.jl](https://github.com/JuliaPy/MicroMamba.jl).
- `System`: Use a pre-installed Conda. If the `exe` preference is set, that is used.
  Otherwise we look for `conda`, `mamba` or `micromamba` in your `PATH`.
- `Current`: Use the currently activated Conda environment instead of creating a new one.
  This backend will only ever install packages, never uninstall. The Conda executable used
  is the same as for the System backend. Similar to the default behaviour of
  [Conda.jl](https://github.com/JuliaPy/Conda.jl).
- `Null`: Don't use CondaPkg to manage dependencies. Use this if you are in a pre-existing
  Conda environment that already satisfies the dependencies of your project. It is up to you
  to ensure any required packages are installed.

The default backend is an implementation detail, but is currently `MicroMamba`.

If you set the `exe` preference but not the `backend` preference then the `System` backend
is used.

### Offline mode

You may activate "offline mode" by setting the preference `offline=true`.
This will prevent CondaPkg from attempting to download or
install new packages. In this case, it is up to you to ensure that any required packages are
already available (such as by having previously called `CondaPkg.resolve()`).

### Conda environment path

By default, CondaPkg installs Conda packages into the current project, so that different
projects can have different dependencies. If you wish to centralize the Conda environment,
you can set one of these preferences:
- `env=@<name>` for a named shared environment, stored in `~/.julia/conda_environments/<name>`.
- `env=<some absolute path>` for a shared environment at the given path.
- `backend=Current` to use the currently activated Conda environment.

**Warning:** If you do this, the versions specified in a per-julia-version `CondaPkg.toml`
can become un-synchronized with the packages installed in the shared Conda environment.
In this case, you will have to re-resolve the dependencies using `resolve(force=true)`.
This restriction might be alleviated in future CondaPkg versions.

### Verbosity

You can control the verbosity of any `conda` or `pip` commands executed by setting the
`verbosity` preference to a number:
- `-1` is quiet mode.
- `0` is normal mode (the default).
- `1`, `2`, etc. are verbose modes, useful for debugging.

## Frequently Asked Questions

### Can I get my package to use a specific Conda environment?

No. The location of the Conda environment is configured purely by the user. Letting packages
specify this configuration is not composable - if two packages want to set the location of
the environment, then they will be in conflict.

### Can I make the Pkg REPL command work without `using CondaPkg` first?

Yes, you can add the following to your [startup
file](https://docs.julialang.org/en/v1/manual/command-line-interface/#Startup-file)
(`~/.julia/config/startup.jl`):

```julia
Base.identify_package("CondaPkg") === nothing || Base.require(@__MODULE__, :CondaPkg)
```
