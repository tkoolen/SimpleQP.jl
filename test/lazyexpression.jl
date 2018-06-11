module LazyExpressionTest

using Compat
using Compat.Test
using SimpleQP
using StaticArrays

import SimpleQP: setdirty!, MockModel

@testset "basics" begin
    a = 2
    b = 3
    c = 4
    expr = @expression(a + b * c)
    @test expr() == a + b * c
end

@testset "bad expression" begin
    @test_throws(ArgumentError, @expression x ? y : z)
end

@testset "parameter" begin
    model = MockModel()
    a = 3
    b = 4.0
    cval = Ref(0)
    c = Parameter{Int}(() -> cval[], model)
    expr = @expression(a + b * c)

    @test expr() == a + b * cval[]
    cval[] = 4
    setdirty!(c)
    @test expr() == a + b * cval[]
end

@testset "nested" begin
    model = MockModel()
    a = 3
    b = 4.0
    cval = Ref(5)
    c = Parameter{Int}(() -> cval[], model)
    expr1 = @expression(a + b * c)
    expr2 = @expression(4 * expr1)
    @test expr2() == 4 * expr1()
    show(devnull, expr1)
end

module M
export SpatialMat, angular, linear
struct SpatialMat
    angular::Matrix{Float64}
    linear::Matrix{Float64}
end
angular(mat::SpatialMat) = mat.angular
linear(mat::SpatialMat) = mat.linear
end

using .M

@testset "user functions" begin
    mat = SpatialMat(rand(3, 4), rand(3, 4))
    scalar = Ref(1.0)
    updatemat! = let scalar = scalar # https://github.com/JuliaLang/julia/issues/15276
        mat -> (mat.angular .= scalar[]; mat.linear .= scalar[]; mat)
    end
    model = MockModel()
    pmat = Parameter(updatemat!, mat, model)
    pmat_angular = @expression angular(pmat)
    result = pmat_angular()
    @test result === angular(mat)
    @test all(result .== scalar[])

    setdirty!(model)
    allocs = @allocated begin
        setdirty!(model)
        pmat_angular()
    end
    @test allocs == 0
end

@testset "matvecmul!" begin
    m = MockModel()
    A = Parameter(rand!, zeros(3, 4), m)
    x = Variable.(1 : 4)
    expr = @expression A * x
    @test expr() == A() * x
    setdirty!(m)
    allocs = @allocated begin
        setdirty!(m)
        expr()
    end
    @test allocs == 0

    wrapped = SimpleQP.WrappedExpression{Vector{AffineFunction{Float64}}}(expr)
    setdirty!(m)
    @test wrapped() == expr()
    allocs = @allocated begin
        setdirty!(m)
        wrapped()
    end
    @test allocs == 0
end

@testset "StaticArrays" begin
    m = MockModel()
    A = Parameter{SMatrix{3, 3, Int, 9}}(m) do
        @SMatrix ones(Int, 3, 3)
    end
    x = Variable.(1 : 3)

    expr1 = @expression A * x
    @test expr1() == A() * x
    setdirty!(A)
    allocs = @allocated expr1()
    @test allocs == 0
    @test expr1() isa SVector{3, AffineFunction{Int}}

    y = SVector{3}(x)
    expr2 = @expression y + y
    @test expr2() == y + y
    allocs = @allocated expr2()
    @test allocs == 0
    @test expr2() isa SVector{3, AffineFunction{Int}}

    expr3 = @expression y - y
    @test expr3() == y - y
    allocs = @allocated expr3()
    @test allocs == 0
    @test expr3() isa SVector{3, AffineFunction{Int}}
end

@testset "mul! optimization" begin
    m = MockModel()
    weight = Parameter(() -> 3, m)
    x = Variable.(1 : 3)
    expr = @expression weight * (x ⋅ x)
    vals = Dict(zip(x, [1, 2, 3]))
    xvals = getindex.(vals, x)
    @test expr()(vals) == 3 * xvals ⋅ xvals
    allocs = @allocated expr()
    @test allocs == 0
end

@testset "vcat optimization" begin
    model = MockModel()
    x = Parameter(zeros(2), model) do x
        x[1] = 1
        x[2] = 2
    end
    y = Parameter(zeros(2), model) do y
        y[1] = 3
        y[2] = 4
    end
    v1 = @expression vcat(x, y)
    @test v1() == [1,2,3,4]
    setdirty!(model)
    @test (@allocated begin
        setdirty!(model)
        v1()
    end) == 0

    # Make sure we expand vcat expressions
    v2 = @expression [x; y]
    @test v2() == [1,2,3,4]
    @test (@allocated begin
        setdirty!(model)
        v2()
    end) == 0

    # Make sure static arrays still work
    z = Parameter{SVector{3, Float64}}(model) do
        SVector(3., 2., 1.)
    end
    v3 = @expression [z; z]
    @test v3() == [3, 2, 1, 3, 2, 1]
    @test (@allocated begin
        setdirty!(model)
        v3()
    end) == 0

    # Other numbers of arguments
    v4 = @expression vcat(x)
    @test v4() == [1, 2]
    @test (@allocated begin
        setdirty!(model)
        v4()
    end) == 0

    v5 = @expression vcat(x, y, x)
    @test v5() == [1, 2, 3, 4, 1, 2]
    @test (@allocated begin
        setdirty!(model)
        v5()
    end) == 0

    # Mixed arguments
    v6 = @expression vcat(x, 3)
    @test v6() == [1, 2, 3]
    @test (@allocated begin
        setdirty!(model)
        v6()
    end) == 0

    v7 = @expression vcat(x, z)
    @test v7() == [1, 2, 3, 2, 1]
    @test (@allocated begin
        setdirty!(model)
        v7()
    end) == 0

    # This shouldn't allocate memory, but it does. If that becomes a problem,
    # we can revisit. 
    @test (@expression vcat(x, 3, y, z))() == [1, 2, 3, 3, 4, 3, 2, 1]

    # Generic fallbacks that allocate memory but should still give the right answer
    @test (@expression vcat(x', y'))() == [1 2; 3 4]
end

end
