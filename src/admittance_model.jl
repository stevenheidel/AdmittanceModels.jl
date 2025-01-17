export AdmittanceModel
"""
An abstract representation of a linear mapping from inputs `x` to outputs `y` of the form
`YΦ = Px`, `y = QᵀΦ`. Subtypes U <: AdmittanceModel are expected to implement:

    get_Y(am::U)
    get_P(am::U)
    get_Q(am::U)
    get_ports(am::U)
    partial_copy(am::U; Y, P, ports)
    compatible(AbstractVector{U})
"""
abstract type AdmittanceModel{T} end

export get_Y
"""
    get_Y(pso::PSOModel)
    get_Y(bbox::Blackbox)

Return a vector of admittance matrices.
"""
function get_Y end

export get_P
"""
    get_P(pso::PSOModel)
    get_P(bbox::Blackbox)

Return an input port matrix.
"""
function get_P end

export get_Q
"""
    get_Q(pso::PSOModel)
    get_Q(bbox::Blackbox)

Return an output port matrix.
"""
function get_Q end

export get_ports
"""
    get_ports(pso::PSOModel)
    get_ports(bbox::Blackbox)

Return a vector of port identifiers.
"""
function get_ports end

export partial_copy
"""
    partial_copy(pso::PSOModel{T, U};
        Y::Union{Vector{V}, Nothing}=nothing,
        P::Union{V, Nothing}=nothing,
        Q::Union{V, Nothing}=nothing,
        ports::Union{AbstractVector{W}, Nothing}=nothing) where {T, U, V, W}

    partial_copy(bbox::Blackbox{T, U};
        Y::Union{Vector{V}, Nothing}=nothing,
        P::Union{V, Nothing}=nothing,
        Q::Union{V, Nothing}=nothing,
        ports::Union{AbstractVector{W}, Nothing}=nothing) where {T, U, V, W}

Create a new model with the same fields except those given as keyword arguments.
"""
function partial_copy end

export compatible
"""
    compatible(psos::AbstractVector{PSOModel{T, U}}) where {T, U}
    compatible(bboxes::AbstractVector{Blackbox{T, U}}) where {T, U}

Check if the models can be cascaded. Always true for PSOModels and true for Blackboxes
that share the same value of `ω`.
"""
function compatible end

export canonical_gauge
"""
    canonical_gauge(pso::PSOModel)
    canonical_gauge(bbox::Blackbox)

Apply an invertible transformation that takes the model to coordinates in which
`P` is `[I ; 0]` (up to floating point errors). Note this will create a dense model.
"""
function canonical_gauge end

import Base: ==
function ==(am1::AdmittanceModel, am2::AdmittanceModel)
    t = typeof(am1)
    if typeof(am2) != t
        return false
    end
    return all([getfield(am1, name) == getfield(am2, name) for name in fieldnames(t)])
end

import Base: isapprox
function isapprox(am1::AdmittanceModel, am2::AdmittanceModel)
    t = typeof(am1)
    if typeof(am2) != t
        return false
    end
    return all([getfield(am1, name) ≈ getfield(am2, name) for name in fieldnames(t)])
end

export apply_transform
"""
    apply_transform(am::AdmittanceModel, transform::AbstractMatrix{<:Number})

Apply a linear transformation `transform` to the coordinates of the model.
"""
function apply_transform(am::AdmittanceModel, transform::AbstractMatrix{<:Number})
    Y = [transpose(transform) * m * transform for m in get_Y(am)]
    P = eltype(Y)(transpose(transform) * get_P(am))
    Q = eltype(Y)(transpose(transform) * get_Q(am))
    return partial_copy(am, Y=Y, P=P, Q=Q)
end

export cascade
"""
    cascade(ams::AbstractVector{U}) where {T, U <: AdmittanceModel{T}}
    cascade(ams::Vararg{U}) where {T, U <: AdmittanceModel{T}}

Cascade the models into one larger block diagonal model.
"""
function cascade(ams::AbstractVector{U}) where {T, U <: AdmittanceModel{T}}
    @assert length(ams) >= 1
    if length(ams) == 1
        return ams[1]
    end
    @assert compatible(ams)
    Y = [cat(m..., dims=(1,2)) for m in zip([get_Y(am) for am in ams]...)]
    P = cat([get_P(am) for am in ams]..., dims=(1,2))
    Q = cat([get_Q(am) for am in ams]..., dims=(1,2))
    ports = vcat([get_ports(am) for am in ams]...)
    return partial_copy(ams[1], Y=Y, P=P, Q=Q, ports=ports)
end

cascade(ams::Vararg{U}) where {T, U <: AdmittanceModel{T}} = cascade(collect(ams))

export ports_to_indices
"""
    ports_to_indices(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    ports_to_indices(am::AdmittanceModel{T}, ports::Vararg{T}) where T

Find the indices corresponding to given ports.
"""
function ports_to_indices(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    am_ports = get_ports(am)
    return [findfirst(isequal(p), am_ports) for p in ports]
end

ports_to_indices(am::AdmittanceModel{T}, ports::Vararg{T}) where T =
    ports_to_indices(am, collect(ports))

export unite_ports
"""
    unite_ports(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    unite_ports(am::AdmittanceModel{T}, ports::Vararg{T}) where T

Unite the given ports into one port.
"""
function unite_ports(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    if length(ports) <= 1
        return am
    end
    port_inds = ports_to_indices(am, ports)
    keep_inds = filter(x -> !(x in port_inds[2:end]),
        1:length(get_ports(am))) # keep the first port
    P = get_P(am)
    first_vector = P[:, port_inds[1]]
    constraint_mat = transpose(hcat([first_vector - P[:, i] for i in port_inds[2:end]]...))
    constrained_am = apply_transform(am, nullbasis(constraint_mat))
    return partial_copy(constrained_am, P=get_P(constrained_am)[:, keep_inds],
        Q=get_Q(constrained_am)[:, keep_inds], ports=get_ports(constrained_am)[keep_inds])
end

unite_ports(am::AdmittanceModel{T}, ports::Vararg{T}) where T =
    unite_ports(am, collect(ports))

export open_ports
"""
    open_ports(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    open_ports(am::AdmittanceModel{T}, ports::Vararg{T}) where T

Remove the given ports.
"""
function open_ports(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    if length(ports) == 0
        return am
    end
    port_inds = ports_to_indices(am, ports)
    keep_inds = filter(x -> !(x in port_inds), 1:length(get_ports(am)))
    return partial_copy(am, P=get_P(am)[:, keep_inds],
        Q=get_Q(am)[:, keep_inds], ports=get_ports(am)[keep_inds])
end

open_ports(am::AdmittanceModel{T}, ports::Vararg{T}) where T =
    open_ports(am, collect(ports))

export open_ports_except
"""
    open_ports_except(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    open_ports_except(am::AdmittanceModel{T}, ports::Vararg{T}) where T

Remove all ports except those specified.
"""
function open_ports_except(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    return open_ports(am, filter(x -> !(x in ports), get_ports(am)))
end

open_ports_except(am::AdmittanceModel{T}, ports::Vararg{T}) where T =
    open_ports_except(am, collect(ports))

export short_ports
"""
    short_ports(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    short_ports(am::AdmittanceModel{T}, ports::Vararg{T}) where T

Replace the given ports by short circuits.
"""
function short_ports(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    if length(ports) == 0
        return am
    end
    port_inds = ports_to_indices(am, ports)
    keep_inds = filter(x -> !(x in port_inds), 1:length(get_ports(am)))
    constraint_mat = transpose(hcat([get_P(am)[:, i] for i in port_inds]...))
    constrained_am = apply_transform(am, nullbasis(constraint_mat))
    return partial_copy(constrained_am, P=get_P(constrained_am)[:, keep_inds],
        Q=get_Q(constrained_am)[:, keep_inds], ports=get_ports(constrained_am)[keep_inds])
end

short_ports(am::AdmittanceModel{T}, ports::Vararg{T}) where T =
    short_ports(am, collect(ports))

export short_ports_except
"""
    short_ports_except(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    short_ports_except(am::AdmittanceModel{T}, ports::Vararg{T}) where T

Replace all ports with short circuits, except those specified.
"""
function short_ports_except(am::AdmittanceModel{T}, ports::AbstractVector{T}) where T
    return short_ports(am, filter(x -> !(x in ports), get_ports(am)))
end

short_ports_except(am::AdmittanceModel{T}, ports::Vararg{T}) where T =
    short_ports_except(am, collect(ports))

export cascade_and_unite
"""
    cascade_and_unite(models::AbstractVector{U}) where {T, U <: AdmittanceModel{T}}
    cascade_and_unite(models::Vararg{U}) where {T, U <: AdmittanceModel{T}}

Cascade all models and unite ports with the same name.
"""
function cascade_and_unite(models::AbstractVector{U}) where {T, U <: AdmittanceModel{T}}
    @assert length(models) >= 1
    if length(models) == 1
        return models[1]
    end
    # number the ports so that the names are all distinct and then cascade
    port_number = 1
    function rename(model::U)
        ports = [(port_number + i - 1, port) for (i, port) in enumerate(get_ports(model))]
        port_number += length(ports)
        return partial_copy(model, ports=ports)
    end
    model = cascade(map(rename, models))
    # merge all ports with the same name
    original_ports = vcat([get_ports(m) for m in models]...)
    for port in unique(original_ports)
        inds = findall([p[2] == port for p in get_ports(model)])
        model = unite_ports(model, get_ports(model)[inds])
    end
    # remove numbering
    return partial_copy(model, ports=[p[2] for p in get_ports(model)])
end

cascade_and_unite(models::Vararg{U}) where {T, U <: AdmittanceModel{T}} =
    cascade_and_unite(collect(models))
