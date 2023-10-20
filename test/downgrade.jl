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
        if pkg != "julia"
            ver2 = "~$ver"
            lines[i] = "$pkg$eq$ver2$post"
            println("downgraded compat for $pkg: $ver -> $ver2")
        end
    elseif compat
        compat = false
    end
end
open("Project.toml", "w") do io
    for line in lines
        println(io, line)
    end
end
