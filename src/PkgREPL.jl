module PkgREPL

import ..CondaPkg
import Pkg
import Markdown

### status

function status()
    CondaPkg.status()
end

const status_help = Markdown.parse("""
```
conda [st|status]
```

Display information about the Conda environment.
""")

const status_spec = Pkg.REPLMode.CommandSpec(
    name = "status",
    short_name = "st",
    api = status,
    help = status_help,
    description = "information about the Conda environment",
)

### resolve

function resolve()
    CondaPkg.resolve()
end

const resolve_help = Markdown.parse("""
```
conda resolve
```

Ensure all Conda dependencies are installed into the environment.
""")

const resolve_spec = Pkg.REPLMode.CommandSpec(
    name = "resolve",
    api = resolve,
    help = resolve_help,
    description = "ensure all Conda dependencies are installed",
)

### add

function add(args; mode=:package, resolve=false)
    if mode == :package
        for arg in args
            CondaPkg.add(arg)
        end
    elseif mode == :channel
        for arg in args
            CondaPkg.add_channel(arg)
        end
    elseif mode == :pip
        for arg in args
            CondaPkg.add_pip(arg)
        end
    end
    if resolve
        CondaPkg.resolve()
    end
end

const add_help = Markdown.parse("""
```
conda add [-c|--channel] [--pip] [-r|--resolve] pkg ...
```

Add packages or channels to the environment.

This adds Conda packages by default. Use `--channel` or `-c` to add channels instead, or
`--pip` to add Pip packages.

The Conda environment is not immediately resolved. Use the `--resolve` or `-r`
flag to force resolve.

!!! note

    Currently there is no syntax to specify the version of a package.
    You can use `CondaPkg.add()` instead.

**Examples**
```
pkg> conda add python
pkg> conda add --channel anaconda
pkg> conda add --pip build
```
""")

const channel_opt = Pkg.REPLMode.OptionDeclaration([
    :name => "channel",
    :short_name => "c",
    :api => :mode => :channel,
])

const pip_opt = Pkg.REPLMode.OptionDeclaration([
    :name => "pip",
    :api => :mode => :pip,
])

const resolve_opt = Pkg.REPLMode.OptionDeclaration([
    :name => "resolve",
    :short_name => "r",
    :api => :resolve => true,
])

const add_spec = Pkg.REPLMode.CommandSpec(
    name = "add",
    api = add,
    should_splat = false,
    help = add_help,
    description = "add Conda packages or channels",
    arg_count = 0 => Inf,
    option_spec = [channel_opt, pip_opt, resolve_opt],
)

### rm

function rm(args; mode=:package, resolve=false)
    if mode == :package
        for arg in args
            CondaPkg.rm(arg)
        end
    elseif mode == :channel
        for arg in args
            CondaPkg.rm_channel(arg)
        end
    elseif mode == :pip
        for arg in args
            CondaPkg.rm_pip(arg)
        end
    end
    if resolve
        CondaPkg.resolve()
    end
end

const rm_help = Markdown.parse("""
```
conda rm [-c|--channel] [--pip] [-r|--resolve] pkg ...
```

Remove packages or channels from the environment.

This removes Conda packages by default. Use `--channel` or `-c` to remove channels instead,
or `--pip` to remove Pip packages.

The Conda environment is not immediately resolved. Use the `--resolve` or `-r`
flag to force resolve.

!!! note

    Currently there is no syntax to specify the version of a package.
    You can use `CondaPkg.rm()` instead.

**Examples**
```
pkg> conda rm python
pkg> conda rm --channel anaconda
pkg> conda rm --pip build
```
""")

const rm_spec = Pkg.REPLMode.CommandSpec(
    name = "remove",
    short_name = "rm",
    api = rm,
    should_splat = false,
    help = rm_help,
    description = "remove Conda packages or channels",
    arg_count = 0 => Inf,
    option_spec = [channel_opt, pip_opt, resolve_opt],
)

### gc

function gc()
    CondaPkg.gc()
end

const gc_help = Markdown.parse("""
```
conda gc
```

Delete any files no longer used by Conda.
""")

const gc_spec = Pkg.REPLMode.CommandSpec(
    name = "gc",
    api = gc,
    help = gc_help,
    description = "delete files no longer used by Conda",
)

## run

function run(args)
    CondaPkg.withenv() do
        Base.run(Cmd(args))
    end
end

const run_help = Markdown.parse("""
```
conda run cmd ...
```

Run the given command in the Conda environment.
""")

const run_spec = Pkg.REPLMode.CommandSpec(
    name = "run",
    api = run,
    should_splat = false,
    help = run_help,
    arg_count = 1 => Inf,
    description = "run a command in the Conda environment",
)

### all specs

const SPECS = Dict(
    "st" => status_spec,
    "status" => status_spec,
    "resolve" => resolve_spec,
    "add" => add_spec,
    "remove" => rm_spec,
    "rm" => rm_spec,
    "gc" => gc_spec,
    "run" => run_spec,
)

function __init__()
    # add the commands to the repl
    Pkg.REPLMode.SPECS["conda"] = SPECS
    # update the help with the new commands
    copy!(Pkg.REPLMode.help.content, Pkg.REPLMode.gen_help().content)
end

end
