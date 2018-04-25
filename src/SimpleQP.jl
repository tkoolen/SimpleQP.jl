__precompile__()

module SimpleQP

# types
export
    Variable,
    Model

# modules
export
    Senses

# functions
export
    quad,
    setobjective!,
    add_nonnegative_constraint!,
    add_nonpositive_constraint!,
    add_zero_constraint!,
    solve!

# macros
export
    @constraint

using Compat
import MathOptInterface
import MacroTools: @capture

const MOI = MathOptInterface
const MOIU = MathOptInterface.Utilities

include("util.jl")
include("functions.jl")

using .Functions

include("moi_interop.jl")
include("model.jl")
include("macros.jl")

end # module
