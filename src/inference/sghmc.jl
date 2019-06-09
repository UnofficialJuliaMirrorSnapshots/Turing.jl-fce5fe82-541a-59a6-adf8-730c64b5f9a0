###
### Stochastic Gradient Hamiltonian Samplers
###


####
#### Stochastic Gradient Hamiltonian Monte Carlo sampler.
####

"""
    SGHMC(n_iters::Int, learning_rate::Float64, momentum_decay::Float64)

Stochastic Gradient Hamiltonian Monte Carlo sampler.

Usage:

```julia
SGHMC(1000, 0.01, 0.1)
```

Arguments:

- `n_iters::Int` : Number of samples to pull.
- `learning_rate::Float64` : The learning rate.
- `momentum_decay::Float64` : Momentum decay variable.

"""
mutable struct SGHMC{AD, T} <: StaticHamiltonian{AD}
    n_iters::Int       # number of samples
    learning_rate::Float64   # learning rate
    momentum_decay::Float64   # momentum decay
    space::Set{T}    # sampling space, emtpy means all
    metricT::Type{<:AHMC.AbstractMetric}
end
SGHMC(args...) = SGHMC{ADBackend()}(args...)

function SGHMC{AD}(
    n_iters,
    learning_rate,
    momentum_decay;
    metricT=AHMC.UnitEuclideanMetric
    ) where AD
    return SGHMC{AD, Any}(n_iters, learning_rate, momentum_decay, Set(), metricT)
end
function SGHMC{AD}(
    n_iters,
    learning_rate,
    momentum_decay,
    space...;
    metricT=AHMC.UnitEuclideanMetric
) where AD
    _space = isa(space, Symbol) ? Set([space]) : Set(space)
    return SGHMC{AD, eltype(_space)}(n_iters, learning_rate, momentum_decay, _space, metricT)
end

function step(
    model,
    spl::Sampler{<:SGHMC},
    vi::VarInfo,
    is_first::Val{true};
    kwargs...
)
    spl.selector.tag != :default && link!(vi, spl)

    # Initialize velocity
    v = zeros(Float64, size(vi[spl]))
    spl.info[:v] = v

    spl.selector.tag != :default && invlink!(vi, spl)
    return vi, true
end

function step(
    model,
    spl::Sampler{<:SGHMC},
    vi::VarInfo,
    is_first::Val{false};
    kwargs...
)
    # Set parameters
    η, α = spl.alg.learning_rate, spl.alg.momentum_decay
    spl.info[:eval_num] = 0

    Turing.DEBUG && @debug "X-> R..."
    if spl.selector.tag != :default
        link!(vi, spl)
        runmodel!(model, vi, spl)
    end

    Turing.DEBUG && @debug "recording old variables..."
    θ, v = vi[spl], spl.info[:v]
    _, grad = gradient_logp(θ, vi, model, spl)
    verifygrad(grad)

    # Implements the update equations from (15) of Chen et al. (2014).
    Turing.DEBUG && @debug "update latent variables and velocity..."
    θ .+= v
    v .= (1 - α) .* v .+ η .* grad .+ rand.(Normal.(zeros(length(θ)), sqrt(2 * η * α)))

    Turing.DEBUG && @debug "saving new latent variables..."
    vi[spl] = θ

    Turing.DEBUG && @debug "R -> X..."
    spl.selector.tag != :default && invlink!(vi, spl)

    Turing.DEBUG && @debug "always accept..."
    return vi, true
end


####
#### Stochastic Gradient Langevin Dynamics sampler.
####

"""
    SGLD(n_iters::Int, ϵ::Float64)

 Stochastic Gradient Langevin Dynamics sampler.

Usage:

```julia
SGLD(1000, 0.5)
```

Arguments:

- `n_iters::Int` : Number of samples to pull.
- `ϵ::Float64` : The scaling factor for the learing rate.

Reference:

Welling, M., & Teh, Y. W. (2011).  Bayesian learning via stochastic gradient Langevin dynamics.
In Proceedings of the 28th international conference on machine learning (ICML-11) (pp. 681-688).
"""
mutable struct SGLD{AD, T} <: StaticHamiltonian{AD}
    n_iters :: Int       # number of samples
    ϵ :: Float64   # constant scale factor of learning rate
    space   :: Set{T}    # sampling space, emtpy means all
    metricT :: Type{<:AHMC.AbstractMetric}
end

SGLD(args...; kwargs...) = SGLD{ADBackend()}(args...; kwargs...)

function SGLD{AD}(
    n_iters,
    ϵ;
    metricT=AHMC.UnitEuclideanMetric
) where AD
    SGLD{AD, Any}(n_iters, ϵ, Set(), metricT)
end

function SGLD{AD}(
    n_iters,
    ϵ,
    space...;
    metricT=AHMC.UnitEuclideanMetric
) where AD
    _space = isa(space, Symbol) ? Set([space]) : Set(space)
    return SGLD{AD, eltype(_space)}(n_iters, ϵ, _space, metricT)
end

function step(
    model,
    spl::Sampler{<:SGLD},
    vi::VarInfo,
    is_first::Val{true};
    kwargs...
)
    spl.selector.tag != :default && link!(vi, spl)

    mssa = AHMC.Adaptation.ManualSSAdaptor(AHMC.Adaptation.MSSState(spl.alg.ϵ))
    spl.info[:adaptor] = AHMC.NaiveHMCAdaptor(AHMC.UnitPreconditioner(), mssa)

    spl.selector.tag != :default && invlink!(vi, spl)
    return vi, true
end

function step(
    model,
    spl::Sampler{<:SGLD},
    vi::VarInfo,
    is_first::Val{false};
    kwargs...
)
    # Update iteration counter
    spl.info[:i] += 1
    spl.info[:eval_num] = 0

    Turing.DEBUG && @debug "compute current step size..."
    γ = .35
    ϵ_t = spl.alg.ϵ / spl.info[:i]^γ # NOTE: Choose γ=.55 in paper
    mssa = spl.info[:adaptor].ssa
    mssa.state.ϵ = ϵ_t

    Turing.DEBUG && @debug "X-> R..."
    if spl.selector.tag != :default
        link!(vi, spl)
        runmodel!(model, vi, spl)
    end

    Turing.DEBUG && @debug "recording old variables..."
    θ = vi[spl]
    _, grad = gradient_logp(θ, vi, model, spl)
    verifygrad(grad)

    Turing.DEBUG && @debug "update latent variables..."
    θ .+= ϵ_t .* grad ./ 2 .- rand.(Normal.(zeros(length(θ)), sqrt(ϵ_t)))

    Turing.DEBUG && @debug "always accept..."
    vi[spl] = θ

    Turing.DEBUG && @debug "R -> X..."
    spl.selector.tag != :default && invlink!(vi, spl)

    return vi, true
end
