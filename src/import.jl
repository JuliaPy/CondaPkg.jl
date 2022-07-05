

"""
import_conda_env(yaml_file::String; overwrite::Bool=false)

Import a conda environment.yml file into the CondaPkg.toml format
"""
function import_conda_env(yaml_file::String; overwrite::Bool=false)
    # get the current CondaPkg.toml file
    dfile = cur_deps_file()

    if isfile(dfile) & !overwrite
        error("There is an existing CondaPkg.toml file: $dfile.",
                "Set overwrite=true to replace this file.")
    end

    env = YAML.load_file(yaml_file)

    # add channels
    for channel in env["channels"]
        if channel != "defaults"
            CondaPkg.add_channel(channel)
        end
    end

    # add dependencies
    for dep in env["dependencies"]
        println(dep)
        import_dependency(dep)
    end


    CondaPkg.resolve()
end

"""
    function import_dependency(dep::String)

Import a basic conda dependency. This is either just
a package, or a package + verion.

Examples:
- pandas
- pandas=1.4
"""
function import_dependency(dep::String)
    if occursin("=", dep)
        split_dep = split(dep, "=")
        CondaPkg.add(split_dep[1]; version="="*split_dep[2], resolve=false)
    else
        CondaPkg.add(dep; resolve=false)
    end
    return nothing
end


"""
    function import_dependency(dep::String)

Import pip packages into CondaPkg.toml

Example yaml file:

```
name: test_env
channels:
  - defaults
  - conda-forge
dependencies:
- pip:
    - Flask-Testing
```
"""
function import_dependency(dep::Dict)
    for pip_dep in dep["pip"]
        if occursin("=", pip_dep)
            split_dep = split(pip_dep, "=")
            CondaPkg.add_pip(split_dep[1]; version="=="*split_dep[2], resolve=false)
        else
            CondaPkg.add_pip(pip_dep; resolve=false)
        end
    end
    return nothing
end