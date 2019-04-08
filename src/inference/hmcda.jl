"""
    HMCDA(n_iters::Int, n_adapts::Int, delta::Float64, lambda::Float64)

Hamiltonian Monte Carlo sampler with Dual Averaging algorithm.

Usage:

```julia
HMCDA(1000, 200, 0.65, 0.3)
```

Arguments:

- `n_iters::Int` : Number of samples to pull.
- `n_adapts::Int` : Numbers of samples to use for adaptation.
- `delta::Float64` : Target acceptance rate. 65% is often recommended.
- `lambda::Float64` : Target leapfrop length.

Example:

```julia
# Define a simple Normal model with unknown mean and variance.
@model gdemo(x) = begin
  s ~ InverseGamma(2,3)
  m ~ Normal(0, sqrt(s))
  x[1] ~ Normal(m, sqrt(s))
  x[2] ~ Normal(m, sqrt(s))
  return s, m
end

sample(gdemo([1.5, 2]), HMCDA(1000, 200, 0.65, 0.3))
```

For more information, please view the following paper ([arXiv link](https://arxiv.org/abs/1111.4246)):

Hoffman, Matthew D., and Andrew Gelman. "The No-U-turn sampler: adaptively setting path lengths in Hamiltonian Monte Carlo." Journal of Machine Learning Research 15, no. 1 (2014): 1593-1623.
"""
mutable struct HMCDA{AD, T} <: AdaptiveHamiltonian{AD}
    n_iters   ::  Int       # number of samples
    n_adapts  ::  Int       # number of samples with adaption for epsilon
    delta     ::  Float64   # target accept rate
    lambda    ::  Float64   # target leapfrog length
    space     ::  Set{T}    # sampling space, emtpy means all
end
HMCDA(args...) = HMCDA{ADBackend()}(args...)
function HMCDA{AD}(n_adapts::Int, delta::Float64, lambda::Float64, space...) where AD
    _space = isa(space, Symbol) ? Set([space]) : Set(space)
    return HMCDA{AD, eltype(_space)}(1, n_adapts, delta, lambda, _space)
end
function HMCDA{AD}(n_iters::Int, delta::Float64, lambda::Float64) where AD
    n_adapts_default = Int(round(n_iters / 2))
    n_adapts = n_adapts_default > 1000 ? 1000 : n_adapts_default
    return HMCDA{AD, Any}(n_iters, n_adapts, delta, lambda, Set())
end
function HMCDA{AD}(n_iters::Int, n_adapts::Int, delta::Float64, lambda::Float64) where AD
    return HMCDA{AD, Any}(n_iters, n_adapts, delta, lambda, Set())
end
function HMCDA{AD}(n_iters::Int, n_adapts::Int, delta::Float64, lambda::Float64, space...) where AD
    _space = isa(space, Symbol) ? Set([space]) : Set(space)
    return HMCDA{AD, eltype(_space)}(n_iters, n_adapts, delta, lambda, _space)
end

function hmc_step(θ, lj, lj_func, grad_func, H_func, ϵ, alg::HMCDA, momentum_sampler::Function;
                  rev_func=nothing, log_func=nothing)
    θ_new, lj_new, is_accept, τ_valid, α = _hmc_step(
                θ, lj, lj_func, grad_func, H_func, ϵ, alg.lambda, momentum_sampler; rev_func=rev_func, log_func=log_func)
    return θ_new, lj_new, is_accept, α
end
