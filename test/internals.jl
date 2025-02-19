@testitem "PkgSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.PkgSpec("")
    @test_throws Exception CondaPkg.PkgSpec("foo!")
    @test_throws Exception CondaPkg.PkgSpec("foo", version = "foo")
    spec = CondaPkg.PkgSpec(
        "  F...OO_-0  ",
        version = "  =1.2.3  ",
        channel = "  SOME_chaNNEL  ",
    )
    @test spec.name == "f...oo_-0"
    @test spec.version == "=1.2.3"
    @test spec.channel == "SOME_chaNNEL"
end

@testitem "ChannelSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.ChannelSpec("")
    spec = CondaPkg.ChannelSpec("  SOME_chaNNEL  ")
    @test spec.name == "SOME_chaNNEL"
end

@testitem "PipPkgSpec" begin
    include("setup.jl")
    @test_throws Exception CondaPkg.PipPkgSpec("")
    @test_throws Exception CondaPkg.PipPkgSpec("foo!")
    @test_throws Exception CondaPkg.PipPkgSpec("foo", version = "1.2")
    spec = CondaPkg.PipPkgSpec("  F...OO_-0  ", version = "  @./SOME/Path  ")
    @test spec.name == "f-oo-0"
    @test spec.version == "@./SOME/Path"
end

@testitem "meta IO" begin
    include("setup.jl")
    specs = Any[
        CondaPkg.PkgSpec("foo", version = "=1.2.3", channel = "bar"),
        CondaPkg.ChannelSpec("fooo"),
        CondaPkg.PipPkgSpec("foooo", version = "==2.3.4"),
    ]
    for spec in specs
        io = IOBuffer()
        CondaPkg.write_meta(io, spec)
        seekstart(io)
        spec2 = CondaPkg.read_meta(io, typeof(spec))
        @test spec == spec2
        for k in propertynames(spec)
            @test getproperty(spec, k) == getproperty(spec2, k)
        end
    end
end

@testitem "abspathurl" begin
    include("setup.jl")
    @test startswith(CondaPkg.abspathurl("foo"), "file://")
    @test endswith(CondaPkg.abspathurl("foo"), "/foo")
    if Sys.iswindows()
        @test CondaPkg.abspathurl("D:\\Foo\\bar.TXT") == "file:///D:/Foo/bar.TXT"
    else
        @test CondaPkg.abspathurl("/Foo/bar.TXT") == "file:///Foo/bar.TXT"
    end
end

@testitem "_resolve_merge_versions" begin
    include("setup.jl")
    @testset "$(case.v1) $(case.v2)" for case in [
        (v1 = "1.2.3", v2 = "1.2.3", expected = "1.2.3, 1.2.3"),
        (v1 = "1.2.3", v2 = "1.2.4", expected = "1.2.3, 1.2.4"),
        (v1 = "1.2.3", v2 = ">=1.2,<2", expected = "1.2.3, >=1.2,<2"),
        (v1 = ">=1.2,<2", v2 = ">=2.1,<3", expected = ">=1.2,<2, >=2.1,<3"),
        (v1 = "1|2", v2 = "2|3", expected = "1, 2 | 1, 3 | 2, 2 | 2, 3"),
    ]
        @test CondaPkg._resolve_merge_versions(case.v1, case.v2) == case.expected
    end
end

@testitem "_compatible_libstdcxx_ng_version" begin
    include("setup.jl")
    @testset "$new_bound" for new_bound in [nothing, "", "foo"]
        CondaPkg.STATE.test_preferences["libstdcxx_ng_version"] = new_bound
        bound = CondaPkg._compatible_libstdcxx_ng_version()
        if new_bound === nothing || new_bound == ""
            if Sys.islinux()
                if bound !== nothing
                    @test bound isa String
                    @test startswith(bound, ">=")
                end
            else
                @test bound === nothing
            end
        else
            @test bound == new_bound
        end
    end
end

@testitem "_compatible_openssl_version" begin
    include("setup.jl")
    @testset "$new_bound" for new_bound in [nothing, "", "foo"]
        CondaPkg.STATE.test_preferences["openssl_version"] = new_bound
        bound = CondaPkg._compatible_openssl_version()
        if new_bound === nothing || new_bound == ""
            if bound !== nothing
                @test bound isa String
                @test startswith(bound, ">=")
            end
        else
            @test bound == new_bound
        end
    end
end

@testitem "checkpref" begin
    include("setup.jl")

    @testset "$(case.type) conversion" for case in [
        # String conversions
        (type = String, input = "hello", expected = "hello"),

        # Int conversions
        (type = Int, input = "42", expected = 42),
        (type = Int, input = 42, expected = 42),
        (type = Int, input = 42.0, expected = 42),

        # Bool conversions
        (type = Bool, input = "yes", expected = true),
        (type = Bool, input = "true", expected = true),
        (type = Bool, input = "no", expected = false),
        (type = Bool, input = "false", expected = false),
        (type = Bool, input = true, expected = true),
        (type = Bool, input = false, expected = false),

        # Vector{String} conversions
        (type = Vector{String}, input = "", expected = String[]),
        (type = Vector{String}, input = "a b c", expected = ["a", "b", "c"]),
        (type = Vector{String}, input = ["a", "b", "c"], expected = ["a", "b", "c"]),

        # Dict{String,String} conversions
        (
            type = Dict{String,String},
            input = Dict("old" => "new", "foo" => "bar"),
            expected = Dict("old" => "new", "foo" => "bar"),
        ),
        (type = Dict{String,String}, input = "", expected = Dict{String,String}()),
        (type = Dict{String,String}, input = "old->new", expected = Dict("old" => "new")),
        (
            type = Dict{String,String},
            input = "old->new foo->bar",
            expected = Dict("old" => "new", "foo" => "bar"),
        ),
        (
            type = Dict{String,String},
            input = "  old->new   foo->bar  ",
            expected = Dict("old" => "new", "foo" => "bar"),
        ),
        (type = Dict{String,String}, input = String[], expected = Dict{String,String}()),
        (type = Dict{String,String}, input = ["old->new"], expected = Dict("old" => "new")),
        (
            type = Dict{String,String},
            input = ["old->new", "foo->bar"],
            expected = Dict("old" => "new", "foo" => "bar"),
        ),
    ]
        result = CondaPkg.checkpref(case.type, case.input)
        @test result isa case.type
        @test result == case.expected
    end

    @testset "$(case.type) error" for case in [
        (type = String, input = 42),
        (type = String, input = :symbol),
        (type = Bool, input = "invalid"),
        (type = Int, input = "not a number"),
        (type = Vector{String}, input = Any["a", :b, 42]),
    ]
        @test_throws Exception CondaPkg.checkpref(case.type, case.input)
    end
end

@testitem "_resolve_check_allowed_channels" begin
    include("setup.jl")

    # Test no allowed channels set
    packages =
        Dict("foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo", channel = "bad-channel")))
    channels = [CondaPkg.ChannelSpec("conda-forge")]
    @test nothing ===
          CondaPkg._resolve_check_allowed_channels(devnull, packages, channels, nothing)

    # Test package with disallowed channel
    allowed = Set(["conda-forge"])
    packages =
        Dict("foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo", channel = "bad-channel")))
    channels = [CondaPkg.ChannelSpec("conda-forge")]
    @test_throws ErrorException(
        "Package 'foo' in test.toml requires channel 'bad-channel' which is not in allowed channels list",
    ) CondaPkg._resolve_check_allowed_channels(devnull, packages, channels, allowed)

    # Test global channel not allowed
    allowed = Set(["conda-forge"])
    packages = Dict("foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo")))
    channels = [CondaPkg.ChannelSpec("bad-channel")]
    @test_throws ErrorException(
        "The following channels are not in the allowed list: bad-channel",
    ) CondaPkg._resolve_check_allowed_channels(devnull, packages, channels, allowed)

    # Test multiple disallowed global channels
    allowed = Set(["conda-forge"])
    packages = Dict("foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo")))
    channels = [CondaPkg.ChannelSpec("bad1"), CondaPkg.ChannelSpec("bad2")]
    @test_throws ErrorException(
        "The following channels are not in the allowed list: bad1, bad2",
    ) CondaPkg._resolve_check_allowed_channels(devnull, packages, channels, allowed)

    # Test multiple allowed channels
    allowed = Set(["conda-forge", "anaconda"])
    packages = Dict(
        "foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo", channel = "conda-forge")),
        "bar" => Dict("test.toml" => CondaPkg.PkgSpec("bar", channel = "anaconda")),
    )
    channels = [CondaPkg.ChannelSpec("conda-forge"), CondaPkg.ChannelSpec("anaconda")]
    @test nothing ===
          CondaPkg._resolve_check_allowed_channels(devnull, packages, channels, allowed)
end

@testitem "_resolve_order_channels!" begin
    include("setup.jl")

    # Test cases for channel ordering
    cases = [
        # Basic ordering: empty order uses defaults
        (channels = ["b", "a", "c"], order = String[], expected = ["a", "b", "c"]),

        # Basic ordering: explicit complete order
        (channels = ["b", "a", "c"], order = ["c", "a", "b"], expected = ["c", "a", "b"]),

        # Basic ordering: partial order
        (channels = ["b", "a", "c"], order = ["c"], expected = ["c", "a", "b"]),
        (channels = ["b", "a", "c"], order = ["b", "c"], expected = ["b", "c", "a"]),

        # Ellipsis handling: in middle
        (
            channels = ["b", "a", "c", "d"],
            order = ["c", "...", "a"],
            expected = ["c", "b", "d", "a"],
        ),

        # Ellipsis handling: at start
        (
            channels = ["b", "a", "c", "d"],
            order = ["...", "a", "b"],
            expected = ["c", "d", "a", "b"],
        ),

        # Ellipsis handling: at end
        (
            channels = ["b", "a", "c", "d"],
            order = ["d", "b", "..."],
            expected = ["d", "b", "a", "c"],
        ),

        # Special channels: conda-forge prioritized
        (
            channels = ["b", "conda-forge", "a"],
            order = String[],
            expected = ["conda-forge", "a", "b"],
        ),

        # Special channels: all special channels present
        (
            channels = ["b", "conda-forge", "anaconda", "pkgs/main", "a"],
            order = String[],
            expected = ["conda-forge", "anaconda", "pkgs/main", "a", "b"],
        ),

        # Special channels: override with explicit order
        (
            channels = ["conda-forge", "a", "b"],
            order = ["...", "b", "conda-forge"],
            expected = ["a", "b", "conda-forge"],
        ),

        # Special channels: override with explicit order and all special channels present
        (
            channels = ["b", "conda-forge", "a", "pkgs/main", "anaconda"],
            order = ["...", "b", "conda-forge"],
            expected = ["anaconda", "pkgs/main", "a", "b", "conda-forge"],
        ),

        # Deduplication: duplicate channels removed
        (
            channels = ["a", "a", "b", "b", "c"],
            order = String[],
            expected = ["a", "b", "c"],
        ),

        # Deduplication: duplicate order entries ignored
        (
            channels = ["a", "b", "c"],
            order = ["a", "a", "b", "b"],
            expected = ["a", "b", "c"],
        ),

        # Missing channels: order entries that don't exist ignored
        (channels = ["a", "b"], order = ["c", "a", "d", "b"], expected = ["a", "b"]),
    ]

    @testset "$(case.channels) $(case.order)" for case in cases
        # Construct channel objects from strings
        channels = [CondaPkg.ChannelSpec(name) for name in case.channels]

        # Apply ordering in-place
        CondaPkg._resolve_order_channels!(channels, case.order)

        # Check result
        @test [c.name for c in channels] == case.expected
    end
end

@testitem "_resolve_map_channels!" begin
    include("setup.jl")

    # Test empty mapping does nothing
    channels = [CondaPkg.ChannelSpec("conda-forge")]
    packages = Dict("foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo")))
    mapping = Dict{String,String}()
    CondaPkg._resolve_map_channels!(channels, packages, mapping)
    @test channels[1].name == "conda-forge"

    # Test global channel mapping
    channels = [
        CondaPkg.ChannelSpec("conda-forge"),
        CondaPkg.ChannelSpec("old-channel"),
        CondaPkg.ChannelSpec("other-channel"),
    ]
    mapping = Dict("old-channel" => "new-channel", "other-channel" => "mapped-channel")
    CondaPkg._resolve_map_channels!(channels, packages, mapping)
    @test [c.name for c in channels] == ["conda-forge", "new-channel", "mapped-channel"]

    # Test package-specific channel mapping
    channels = [CondaPkg.ChannelSpec("conda-forge")]
    packages = Dict(
        "foo" => Dict(
            "test1.toml" => CondaPkg.PkgSpec("foo", channel = "old-channel"),
            "test2.toml" => CondaPkg.PkgSpec("foo", channel = "other-channel"),
        ),
        "bar" =>
            Dict("test.toml" => CondaPkg.PkgSpec("bar", channel = "unmapped-channel")),
    )
    mapping = Dict("old-channel" => "new-channel", "other-channel" => "mapped-channel")
    CondaPkg._resolve_map_channels!(channels, packages, mapping)
    @test packages["foo"]["test1.toml"].channel == "new-channel"
    @test packages["foo"]["test2.toml"].channel == "mapped-channel"
    @test packages["bar"]["test.toml"].channel == "unmapped-channel"

    # Test both global and package-specific mapping together
    channels = [CondaPkg.ChannelSpec("conda-forge"), CondaPkg.ChannelSpec("old-channel")]
    packages =
        Dict("foo" => Dict("test.toml" => CondaPkg.PkgSpec("foo", channel = "old-channel")))
    mapping = Dict("old-channel" => "new-channel")
    CondaPkg._resolve_map_channels!(channels, packages, mapping)
    @test [c.name for c in channels] == ["conda-forge", "new-channel"]
    @test packages["foo"]["test.toml"].channel == "new-channel"

    # Test that other package properties are preserved
    channels = [CondaPkg.ChannelSpec("old-channel")]
    packages = Dict(
        "foo" => Dict(
            "test.toml" => CondaPkg.PkgSpec(
                "foo",
                version = "1.2.3",
                channel = "old-channel",
                build = "special",
            ),
        ),
    )
    mapping = Dict("old-channel" => "new-channel")
    CondaPkg._resolve_map_channels!(channels, packages, mapping)
    @test packages["foo"]["test.toml"].name == "foo"
    @test packages["foo"]["test.toml"].version == "1.2.3"
    @test packages["foo"]["test.toml"].channel == "new-channel"
    @test packages["foo"]["test.toml"].build == "special"
end
