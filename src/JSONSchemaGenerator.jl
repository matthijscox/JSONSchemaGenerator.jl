module JSONSchemaGenerator

using OrderedCollections
using StructTypes

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

"""
    generate(::Type)::OrderedDict{String, Any}

Generate a JSONSchema in the form of a dictionary
"""
function generate(schema_type::Type)
    d = _generate_json_object(schema_type)
    return d
end

#=
For example:
{
"type": "object",
"properties": {
  "first_name": { "type": "string" },
  "last_name": { "type": "string" },
  "shipping_address": { "$ref": "/schemas/address" },
  "billing_address": { "$ref": "/schemas/address" }
},
"required": ["first_name", "last_name", "shipping_address", "billing_address"]
}
=#
function _generate_json_object(julia_type::Type)
    names = string.(fieldnames(julia_type))
    types = fieldtypes(julia_type)
    d = OrderedDict{String, Any}(
        "type" => "object",
        "properties" => OrderedDict{String, Any}(
            names .=> _generate_json_type_def.(types) # TODO: handling referencing to objects
        ),
        "required" => names, # TODO: remove optional fields of Union{Nothing, T}
    )
    return d
end

function _generate_json_type_def(julia_type::Type)
    return _generate_json_type_def(julia_type::Type, Val(_json_type(julia_type)))
end

function _generate_json_type_def(julia_type::Type, ::Val{:object})
    return OrderedDict{String, String}(
        "\$ref" => _json_reference(julia_type)
    )
end

function _generate_json_type_def(julia_type::Type, ::Val{:enum})
    return OrderedDict{String, String}(
        "enum" => string(_json_type(julia_type))
    )
end

function _generate_json_type_def(julia_type::Type, ::Val)
    return OrderedDict{String, String}(
        "type" => string(_json_type(julia_type))
    )
end

# used in things like { "\$ref": "#/MyObject" }
function _json_reference(julia_type::Type)
    return "#/" * string(julia_type)
end

end
