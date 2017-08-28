using LsqFit: curve_fit
export linear_region, linear_regions
#######################################################################################
# Functions and methods to deduce linear scaling regions
#######################################################################################
"""
    isevenly(a::AbstractVector)
Check if `a` is evenly spaced.
"""
function isevenly(a::AbstractVector)
  test = a[2] - a[1]
  for i in 2:length(a)-1
    if !(a[i+1] - a[i] ≈ test)
      throw(ArgumentError("x-axis is not evenly spaced!"))
    end
  end
  true
end

"""
```julia
linear_region(x, y; dxi::Int = 1, tol = 0.2) -> ([ind1, ind2], slope)
```
Call `linear_regions`, identify the largest linear region (`max_linear_region`)
and approximate the slope of this region using least squares fit.
Return the indeces where
the region starts and stops (`x[ind1:ind2]`) as well as the approximated `slope`.
"""
function linear_region(x::AbstractVector, y::AbstractVector;
  dxi::Int = 1, tol::Real = 0.2)

  # Find biggest linear region:
  reg_ind = max_linear_region(linear_regions(x,y; dxi=dxi, tol=tol)...)
  # Prepare least squares fit:
  xfit = view(x, reg_ind[1]:reg_ind[2])
  yfit = view(y, reg_ind[1]:reg_ind[2])
  p0 = [1.0, 1.0]
  model(x, p) = p[1].*x .+ p[2]
  # Find fit of tangent:
  fit = curve_fit(model, xfit, yfit, p0)
  approx_tang = fit.param[1]
  return reg_ind, approx_tang
end

"""
    max_linear_region(lrs::Vector{Int}, tangents::Vector{Float64})
Find the biggest linear region and return it.
"""
function max_linear_region(lrs::Vector{Int}, tangents::Vector{Float64})
  dis = 0
  tagind = 0
  for i in 1:length(lrs)-1
    if lrs[i+1] - lrs[i] > dis
      dis = lrs[i+1] - lrs[i]
      tagind = i
    end
  end
  return [lrs[tagind], lrs[tagind+1]]
end

"""
```julia
linear_regions(x, y; dxi::Int = 1, tol = 0.2) -> (lrs, tangents)
```
Identify regions where the curve `y(x)` is linear, by scanning the
`x`-axis every `dxi` indeces (e.g. at `x[1] to x[5], x[5] to x[10], x[10] to x[15]`
and so on if `dxi=5`).

If the slope (calculated using `LsqFit`) of a region of width `dxi` is
approximatelly equal to that of the previous region,
within tolerance `tol`,
then these two regions belong to the same linear region.

Return the indeces of `x` that correspond to linear regions, `lrs`,
and the approximated `tangents` at each region. `lrs` is a vector of `Int`.
"""
function linear_regions(x::AbstractVector, y::AbstractVector;
  dxi::Int = 1, tol::Real = 0.2)

  maxit = length(x) ÷ dxi

  tangents = Float64[slope(view(x, 1:max(dxi, 2)), view(y, 1:max(dxi, 2)))]

  prevtang = tangents[1]
  lrs = Int[1] #start of first linear region is always 1
  lastk = 1

  # Start loop over all partitions of `x` into `dxi` intervals:
  for k in 1:maxit-1
    tang = slope(view(x, k*dxi:(k+1)*dxi), view(y, k*dxi:(k+1)*dxi))
    if isapprox(tang, prevtang, rtol=tol)
      # Tanget is similar with initial previous one (based on tolerance)
      continue
    else
      # Tangent is not similar.
      # Push new tangent for a new linear region
      push!(tangents, tang)

      # Set the START of a new linear region
      # which is also the END of the previous linear region
      push!(lrs, k*dxi)
      lastk = k
    end

    # Set new previous tangent (only if it was not the same as current)
    prevtang = tang
  end
  push!(lrs, length(x))
  return lrs, tangents
end

"""
    slope(xdata, ydata)
Perform linear fit to `y(x)` using the module `LsqFit` and return the calculated
slope.
"""
function slope(xfit, yfit)
  p0 = [(yfit[end] - yfit[1])/(xfit[end] - xfit[1]), yfit[1]]
  model(x, p) = p[1].*x .+ p[2]
  # Find fit of tangent:
  curve_fit(model, xfit, yfit, p0).param[1]
end

# This function exists ONLY FOR TESTING! Do not use it elsewhere!
function _plot_lrs(x, y, lrs, tangents)
  for i ∈ 1:length(lrs)-1
    PyPlot.plot(x[lrs[i]:lrs[i+1]], y[lrs[i]:lrs[i+1]])
  end
end

function _plot_lrs(x, y, tol::Real)
  lrs, tang = linear_regions(x, y; tol = tol)
  _plot_lrs(x, y, lrs, tang)
end

#######################################################################################
# Dimensions
#######################################################################################

export boxcounting_dim, capacity_dim, generalized_dim,
information_dim, correlation_dim, collision_dim, estimate_boxsizes,
kaplanyorke_dim

magnitude(x::Real) = round(Int, log10(x))

"""
```julia
estimate_boxsizes(dataset; m = 5, k::Int = 10, n::Int = 3)
```
Return `logspace(magnitude(x), magnitude(x) - n, k)` where `x` is
the `minimum( maximum(abs.(v)) - minimum(abs.(v)) for v in vectors )/m`.

In essense, get a `k`-element `logspace` with maximum being the `1/m` of the
relative order of magnitude of the vectors,
and the minimum being `n` orders of magnitude less.
"""
function estimate_boxsizes(vectors::Vararg{AbstractVector{<:Real}};
  m = 5, k::Int = 10, n::Int = 3)
  # maximum ε is 1/m of maximum - minimum
  maxε = Inf
  for v in vectors
    vv = abs.(v)
    ma = maximum(vv)
    mi = minimum(vv)
    d = (ma - mi)/10
    if d < maxε
      maxε = d
    end
  end
  logspace(magnitude(maxε), magnitude(maxε)-n, k)
end
estimate_boxsizes(dataset::AbstractMatrix{<:Real}) = estimate_boxsizes(d2v(dataset)...)

"""
    generalized_dim(α, dataset) -> D_α
Return the `α` order generalized dimension that corresponds to the given dataset.
This quantity corresponds to the
power law exponent of the scaling of the `genentropy` versus the box size `ε`.

**WARNING** - This call performs a lot of automated steps:

  1. A vector of box sizes is decided by calling `es = estimate_boxsizes(dataset)`.
  2. For each element of `es` the appropriate entropy is
     calculated, through `d[i] = genentropy(α, es[i], dataset)`. Let `x = -log.(es)`.
  3. The curve d(x) is decomposed into linear regions, using `linear_regions(x, d)`.
  4. The biggest linear region is chosen, and a fit for the slope of that
     region is performed using the package `LsqFit` (see `linear_region`).
  5. This fitted slope is returned.

By doing these steps one by one yourself, you can adjust the keyword arguments
given to each of these function calls, refining the accuracy of the result.

The following aliases are provided:

  * α = 0 : `boxcounting_dim`, `capacity_dim`
  * α = 1 : `information_dim`
  * α = 2 : `correlation_dim`, `collision_dim`
"""
function generalized_dim(α, vectors::Vararg{AbstractVector{<:Real}})
  es = estimate_boxsizes(vectors...)
  dd = zeros(es)
  for i in 1:length(es)
    dd[i] = genentropy(α, es[i], vectors...)
  end
  return linear_region(-log.(es), dd)[2]
end
generalized_dim(α, dataset::AbstractMatrix{<:Real}) =
generalized_dim(α, d2v(dataset)...)
# Aliases
"correlation_dim(args...) = generalized_dim(2, args...)"
correlation_dim(args...) = generalized_dim(2, args...)
collision_dim = correlation_dim

"capacity_dim(args...) = generalized_dim(0, args...)"
capacity_dim(args...) = generalized_dim(0, args...)
boxcounting_dim = capacity_dim

"information_dim(args...) = generalized_dim(1, args...)"
information_dim(args...) = generalized_dim(1, args...)

"""
```julia
kaplanyorke_dim(lyapunovs::AbstractVector)
```
Calculate the Kaplan-Yorke dimension [1] (aka Lyapunov dimension).
This simply is the point where
`cumsum(lyapunovs)` becomes zero (interpolated). Returns the dimension of the system
if the sum of the exponents never becomes negative.

[1] :  J. Kaplan & J. Yorke,
*Chaotic behavior of multidimensional difference equations*,
Lecture Notes in Mathematics vol. **730**, Springer (1979)
"""
function kaplanyorke_dim(v::AbstractVector)
  issorted(v, rev = true) || throw(ArgumentError(
  "The lyapunov vector must be sorted from most positive to most negative"))

  s = cumsum(v); k = length(v)
  # Find k such that sum(λ_i for i in 1:k) is still possitive
  for i in eachindex(s)
    if s[i] < 0
      k = i-1
      break
    end
  end

  if k == 0
    return zero(v[1])
  elseif k < length(v)
    return k + s[k]/abs(v[k+1])
  else
    return typeof(v[1])(length(v))
  end
end