module JSONSchemaGenerator

# by default we assume the type is a custom type, which should be a JSON object
_json_type(::Type{<:Any}) = :object
#_json_type(::Type{<:AbstractDict}) = :object

_json_type(::Type{<:AbstractArray}) = :array
_json_type(::Type{Bool}) = :boolean
_json_type(::Type{<:Integer}) = :integer
_json_type(::Type{<:Real}) = :number
_json_type(::Type{Nothing}) = :null
_json_type(::Type{Missing}) = :null
_json_type(::Type{<:AbstractString}) = :string

_is_nothing_union(x::Type) = false
_is_nothing_union(x::Type{Nothing}) = false
_is_nothing_union(x::Type{Union{Nothing, T}}) where T = true

end
