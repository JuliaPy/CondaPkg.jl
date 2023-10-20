# "downgrade" the project by turning dependencies like
#   Foo = "1.2.3"
# into
#   Foo = "~1.2.3"
# so that we get old versions of things installed.
lines = readlines("Project.toml")
compat = false
for (i, line) in pairs(lines)
    if !compat && line == "[compat]"
        global compat = true
    elseif compat && !isempty(line)
        m = match(r"^([A-Za-z0-9]+)( *= *\")([^\"]*)(\".*)", line)
        pkg, eq, ver, post = m.captures
        if pkg in ["julia", "Markdown", "Pkg", "TOML"]
            println("skipping $pkg: $ver")
            continue
        end
        ver2 = strip(split(ver, ",")[1])
        if ver2[1] in "^~="
            op = ver2[1]
            ver2 = ver2[2:end]
        elseif isnumeric(ver2[1])
            op = '^'
        else
            println("skipping $pkg: $ver")
            continue
        end
        if op in "^~" && occursin(r"^0\.[0-9]+\.[0-9]+$", ver2)
            op = '='
        elseif op in "^"
            op = '^'
        end
        ver2 = "$op$ver2"
        if ver == ver2
            println("skipping $pkg: $ver")
            continue
        end
        lines[i] = "$pkg$eq$ver2$post"
        println("downgrading $pkg: $ver -> $ver2")
    elseif compat
        compat = false
    end
end
open("Project.toml", "w") do io
    for line in lines
        println(io, line)
    end
end
