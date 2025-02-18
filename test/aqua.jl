@testitem "Aqua" begin
    import Aqua
    Aqua.test_all(
        CondaPkg;
        # these are loaded lazily
        stale_deps = (ignore = [:MicroMamba, :pixi_jll]),
    )
end
