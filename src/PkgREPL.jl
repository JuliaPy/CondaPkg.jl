module PkgREPL

import ..CondaPkg
import Pkg
import Markdown

### parsing

function parse_pkg(x::String)
    m = match(r"""
    ^
    (?:([^\s\:]+)::)?  # channel
    ([-_.A-Za-z0-9]+)  # name
    (?:\@?([<>=!0-9][^\s\#]*))?  # version
    (?:\#([^\s]+))?  # build
    $
    """x, x)
    m === nothing && error("invalid conda package: $x")
    channel = something(m.captures[1], "")
    name = m.captures[2]
    version = something(m.captures[3], "")
    build = something(m.captures[4], "")
    CondaPkg.PkgSpec(name, version=version, channel=channel, build=build)
end

function parse_pip_pkg(x::String; binary::String="")
    m = match(r"""
    ^
    ([-_.A-Za-z0-9]+)
    ([~!<>=@].*)?
    $
    """x, x)
    m === nothing && error("invalid pip package: $x")
    name = m.captures[1]
    version = something(m.captures[2], "")
    CondaPkg.PipPkgSpec(name, version=version, binary=binary)
end

function parse_channel(x::String)
    CondaPkg.ChannelSpec(x)
end

### options

const force_opt = Pkg.REPLMode.OptionDeclaration([
    :name => "force",
    :short_name => "f",
    :api => :force => true,
])

const binary_opt = Pkg.REPLMode.OptionDeclaration([
    :name => "binary",
    :takes_arg => true,
    :api => :binary => identity,
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

function add(args)
    CondaPkg.add(parse_pkg.(args))
end

const add_help = Markdown.parse("""
```
conda add pkg ...
```

Add packages to the environment.

**Examples**

```
pkg> conda add python
pkg> conda add python>=3.5,<4
pkg> conda add conda-forge::numpy
```
""")

const add_spec = Pkg.REPLMode.CommandSpec(
    name = "add",
    api = add,
    should_splat = false,
    help = add_help,
    description = "add Conda packages",
    arg_count = 0 => Inf,
)

### channel_add

function channel_add(args)
    CondaPkg.add(parse_channel.(args))
end

const channel_add_help = Markdown.parse("""
```
conda channel_add channel ...
```

Add channels to the environment.

**Examples**

```
pkg> conda channel_add conda-forge
```
""")

const channel_add_spec = Pkg.REPLMode.CommandSpec(
    name = "channel_add",
    api = channel_add,
    should_splat = false,
    help = channel_add_help,
    description = "add Conda channels",
    arg_count = 0 => Inf,
)

### pip_add

function pip_add(args; binary="")
    CondaPkg.add([parse_pip_pkg(arg, binary=binary) for arg in args])
end

const pip_add_help = Markdown.parse("""
```
conda pip_add [--binary={only|no}] pkg ...
```

Add Pip packages to the environment.

**Examples**

```
pkg> conda pip_add build~=0.7
pkg> conda pip_add --binary=no nmslib
```
""")

const pip_add_spec = Pkg.REPLMode.CommandSpec(
    name = "pip_add",
    api = pip_add,
    should_splat = false,
    help = pip_add_help,
    description = "add Pip packages",
    arg_count = 0 => Inf,
    option_spec = [binary_opt],
)

### rm

function rm(args)
    CondaPkg.rm(parse_pkg.(args))
end

const rm_help = Markdown.parse("""
```
conda rm|remove pkg ...
```

Remove packages from the environment.

**Examples**

```
pkg> conda rm python
```
""")

const rm_spec = Pkg.REPLMode.CommandSpec(
    name = "remove",
    short_name = "rm",
    api = rm,
    should_splat = false,
    help = rm_help,
    description = "remove Conda packages",
    arg_count = 0 => Inf,
)

### channel_rm

function channel_rm(args)
    CondaPkg.rm(parse_channel.(args))
end

const channel_rm_help = Markdown.parse("""
```
conda channel_rm|channel_remove channel ...
```

Remove channels from the environment.

**Examples**

```
pkg> conda channel_rm conda-forge
```
""")

const channel_rm_spec = Pkg.REPLMode.CommandSpec(
    name = "channel_remove",
    short_name = "channel_rm",
    api = channel_rm,
    should_splat = false,
    help = channel_rm_help,
    description = "remove Conda channels",
    arg_count = 0 => Inf,
)

### pip_rm

function pip_rm(args)
    CondaPkg.rm(parse_pip_pkg.(args))
end

const pip_rm_help = Markdown.parse("""
```
conda pip_rm|pip_remove pkg ...
```

Remove Pip packages from the environment.

**Examples**

```
pkg> conda pip_rm build
```
""")

const pip_rm_spec = Pkg.REPLMode.CommandSpec(
    name = "pip_remove",
    short_name = "pip_rm",
    api = pip_rm,
    should_splat = false,
    help = pip_rm_help,
    description = "remove Pip packages",
    arg_count = 0 => Inf,
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
    "channel_add" => channel_add_spec,
    "channel_remove" => channel_rm_spec,
    "channel_rm" => channel_rm_spec,
    "pip_add" => pip_add_spec,
    "pip_remove" => pip_rm_spec,
    "pip_rm" => pip_rm_spec,
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
