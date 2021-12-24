using CondaPkg
using Test


@testset "Install Python" begin
    CondaPkg.add("python")
    CondaPkg.withenv() do
        pythonpath = joinpath(CondaPkg.envdir(), Sys.iswindows() ? "python.exe" : "bin/python")
        @test isfile(pythonpath)
    end
end

@testset "install/remove python package" begin
    # verify package isn't already installed
    CondaPkg.withenv() do
        @test_throws Exception run(`python -c "import six"`)
    end

    # install package
    CondaPkg.add("six")
    CondaPkg.withenv() do
        run(`python -c "import six"`)
    end

    # remove package
    CondaPkg.rm("six")
    CondaPkg.withenv() do
        @test_throws Exception run(`python -c "import six"`)
    end
end

@testset "pip install/remove python package" begin
    # verify package isn't already installed
    CondaPkg.withenv() do
        @test_throws Exception run(`python -c "import six"`)
    end

    # install package
    CondaPkg.add_pip("six")
    CondaPkg.withenv() do
        run(`python -c "import six"`)
    end

    # remove package
    CondaPkg.rm_pip("six")
    CondaPkg.withenv() do
        @test_throws Exception run(`python -c "import six"`)
    end
end


@testset "Install/uninstall executable package" begin
    # install package, verify that executable exists
    CondaPkg.add("curl")
    curl_path = CondaPkg.which("curl")
    @test isfile(curl_path)

    # test uninstall
    CondaPkg.rm("curl")
    CondaPkg.resolve()
    @test !isfile(curl_path)
end

