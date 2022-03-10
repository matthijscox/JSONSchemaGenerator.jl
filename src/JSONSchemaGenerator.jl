module JSONSchemaGenerator

import OrderedCollections: OrderedDict
import StructTypes

# by default we assume the type is a custom type, which should be a JSON object
_json_type(::Type{<:Any}) = :object
#_json_type(::Type{<:AbstractDict}) = :object

_json_type(::Type{<:AbstractArray}) = :array
_json_type(::Type{Bool}) = :boolean
_json_type(::Type{<:Integer}) = :integer
_json_type(::Type{<:Real}) = :number
_json_type(::Type{Nothing}) = :null
_json_type(::Type{Missing}) = :null
_json_type(::Type{<:Enum}) = :enum
_json_type(::Type{<:AbstractString}) = :string

_is_nothing_union(::Type) = false
_is_nothing_union(::Type{Nothing}) = false
_is_nothing_union(::Type{Union{Nothing, T}}) where T = true

_get_optional_type(::Type{Union{Nothing, T}}) where T = T

"""
    generate(::Type)::OrderedDict{String, Any}

Generate a JSONSchema in the form of a dictionary
"""
function generate(schema_type::Type; nested::Bool=true)
    d = _generate_json_object(schema_type, nested)
    return d
end

# by default we do not resolve nested objects into reference definitions
function _generate_json_object(julia_type::Type, nested::Bool=true)
    names = fieldnames(julia_type)
    types = fieldtypes(julia_type)
    json_property_names = String[]
    required_json_property_names = String[]
    json_properties = []
    for (name, type) in zip(names, types)
        name_string = string(name)
        if _is_nothing_union(type) # we assume it's an optional field type
            @assert applicable(StructTypes.omitempties, julia_type) "we expect StructTypes.omitempties for Union{Nothing, T} fields"
            @assert name in StructTypes.omitempties(julia_type) "we miss $name in $(StructTypes.omitempties(julia_type))"
            type = _get_optional_type(type)
        else
            push!(required_json_property_names, name_string)
        end
        # TODO: handling referencing to objects
        push!(json_properties, _generate_json_type_def(type))
        push!(json_property_names, name_string)
    end
    return OrderedDict{String, Any}(
        "type" => "object",
        "properties" => OrderedDict{String, Any}(
            json_property_names .=> json_properties
        ),
        "required" => required_json_property_names,
    )
end

function _generate_json_type_def(julia_type::Type)
    return _generate_json_type_def(julia_type::Type, Val(_json_type(julia_type)))
end

function _generate_json_type_def(julia_type::Type, ::Val{:object})
    # if !nested && applicable(StructTypes.StructType, julia_type)
    # d = OrderedDict{String, Any}(
    #     "\$ref" => _json_reference(julia_type)
    # )
    # else
    return _generate_json_object(julia_type)
end

function _generate_json_type_def(julia_type::Type, ::Val{:enum})
    return OrderedDict{String, Tuple{Vararg{String}}}(
        "enum" => string.(instances(julia_type))
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
