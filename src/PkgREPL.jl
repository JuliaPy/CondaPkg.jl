module PkgREPL

import ..CondaPkg
import Pkg
import Markdown

### parsing

function parse_pkg(x::String)
    m = match(r"^\s*(([^:]+)::)?([-_.A-Za-z0-9]+)\s*([<>=!0-9].*)?$", x)
    m === nothing && error("invalid conda package: $x")
    channel = m.captures[2]
    name = m.captures[3]
    version = m.captures[4]
    if version === nothing
        version = ""
    end
    if channel === nothing
        channel = ""
    end
    CondaPkg.PkgSpec(name, version=version, channel=channel)
end

function parse_pip_pkg(x::String)
    m = match(r"^\s*([-_.A-Za-z0-9]+)\s*([~!<>=@].*)?$", x)
    m === nothing && error("invalid pip package: $x")
    name = m.captures[1]
    version = m.captures[2]
    if version === nothing
        version = ""
    end
    CondaPkg.PipPkgSpec(name, version=version)
end

function parse_channel(x::String)
    CondaPkg.ChannelSpec(x)
end

### options

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

const force_opt = Pkg.REPLMode.OptionDeclaration([
    :name => "force",
    :short_name => "f",
    :api => :force => true,
])

### status

function status()
    CondaPkg.status()
end

const status_help = Markdown.parse("""
```
conda st|status
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

function resolve(; force=false)
    CondaPkg.resolve(force=force, interactive=true)
end

const resolve_help = Markdown.parse("""
```
conda [-f|--force] resolve
```

Ensure all Conda dependencies are installed into the environment.
""")

const resolve_spec = Pkg.REPLMode.CommandSpec(
    name = "resolve",
    api = resolve,
    help = resolve_help,
    description = "ensure all Conda dependencies are installed",
    option_spec = [force_opt],
)

### add

function add(args; mode=:package, resolve=false)
    if mode == :package
        CondaPkg.add(parse_pkg.(args))
    elseif mode == :channel
        CondaPkg.add(parse_channel.(args))
    elseif mode == :pip
        CondaPkg.add(parse_pip_pkg.(args))
    end
    resolve && CondaPkg.resolve()
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

**Examples**
```
pkg> conda add python
pkg> conda add python>=3.5,<4
pkg> conda add conda-forge::numpy
pkg> conda add --channel anaconda
pkg> conda add --pip build
pkg> conda add --pip build~=0.7.0
```
""")

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
        CondaPkg.rm(parse_pkg.(args))
    elseif mode == :channel
        CondaPkg.rm(parse_channel.(args))
    elseif mode == :pip
        CondaPkg.rm(parse_pip_pkg.(args))
    end
    resolve && CondaPkg.resolve()
end

const rm_help = Markdown.parse("""
```
conda rm|remove [-c|--channel] [--pip] [-r|--resolve] pkg ...
```

Remove packages or channels from the environment.

This removes Conda packages by default. Use `--channel` or `-c` to remove channels instead,
or `--pip` to remove Pip packages.

The Conda environment is not immediately resolved. Use the `--resolve` or `-r`
flag to force resolve.

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
