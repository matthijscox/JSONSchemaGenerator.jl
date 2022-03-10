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

Base.@kwdef mutable struct SchemaSettings
    toplevel::Bool = true # will be set to false by top level schema object
    use_references::Bool = false # create schema references instead of nesting types
    reference_types::Set{DataType}
    reference_path = "#/\$defs/"
end

"""
    schema(::Type)::OrderedDict{String, Any}

Generate a JSONSchema in the form of a dictionary
"""
function schema(schema_type::Type; use_references::Bool=false)
    if use_references
        reference_types = _gather_data_types(schema_type)
    else
        reference_types = Set{DataType}()
    end
    settings = SchemaSettings(
        use_references = use_references,
        reference_types = reference_types,
    )
    d = _generate_json_object(schema_type, settings)
    return d
end

# by default we do not resolve nested objects into reference definitions
function _generate_json_object(julia_type::Type, settings::SchemaSettings)
    is_top_level = settings.toplevel
    if is_top_level
        settings.toplevel = false # downstream types are not toplevel
    end
    names = fieldnames(julia_type)
    types = fieldtypes(julia_type)
    json_property_names = String[]
    required_json_property_names = String[]
    json_properties = []
    for (name, type) in zip(names, types)
        name_string = string(name)
        if _is_nothing_union(type) # we assume it's an optional field type
            @assert name in StructTypes.omitempties(julia_type) "we miss $name in $(StructTypes.omitempties(julia_type))"
            type = _get_optional_type(type)
        else
            push!(required_json_property_names, name_string)
        end
        if settings.use_references && type in settings.reference_types
            push!(json_properties, _json_reference(type, settings))
        else
            push!(json_properties, _generate_json_type_def(type, settings))
        end
        push!(json_property_names, name_string)
    end
    d = OrderedDict{String, Any}(
        "type" => "object",
        "properties" => OrderedDict{String, Any}(
            json_property_names .=> json_properties
        ),
        "required" => required_json_property_names,
    )
    if is_top_level && settings.use_references
        d["\$defs"] = _generate_json_reference_types(settings)
    end
    return d
end

function _generate_json_type_def(julia_type::Type, settings::SchemaSettings)
    return _generate_json_type_def(Val(_json_type(julia_type)), julia_type, settings)
end

function _generate_json_type_def(::Val{:object}, julia_type::Type, settings::SchemaSettings)
    return _generate_json_object(julia_type, settings)
end

function _generate_json_type_def(::Val{:array}, julia_type::Type{<:AbstractArray{T}}, settings::SchemaSettings) where T
    return OrderedDict{String, Any}(
        "type" => "array",
        "items" => _generate_json_type_def(T, settings)
    )
end

function _generate_json_type_def(::Val{:enum}, julia_type::Type, settings::SchemaSettings)
    return OrderedDict{String, Tuple{Vararg{String}}}(
        "enum" => string.(instances(julia_type))
    )
end

function _generate_json_type_def(::Val, julia_type::Type, settings::SchemaSettings)
    return OrderedDict{String, String}(
        "type" => string(_json_type(julia_type))
    )
end

# used in things like { "\$ref": "#/MyObject" }
function _json_reference(julia_type::Type, settings::SchemaSettings)
    return OrderedDict{String, String}(
         "\$ref" => settings.reference_path * string(julia_type)
    )
end

function _generate_json_reference_types(settings::SchemaSettings)
    d = OrderedDict{String, Any}()
    for ref_type in settings.reference_types
        d[string(ref_type)] = _generate_json_type_def(ref_type, settings)
    end
    return d
end

function _gather_data_types(julia_type::Type)::Set{DataType}
    data_types = Set{DataType}()
    for field_type in fieldtypes(julia_type)
        _gather_data_types!(data_types, _get_type_to_gather(field_type))
    end
    return data_types
end

function _gather_data_types!(data_types::Set{DataType}, julia_type::Type)::Nothing
    if StructTypes.StructType(julia_type) isa StructTypes.DataType
        push!(data_types, julia_type)
        for field_type in fieldtypes(julia_type)
            _gather_data_types!(data_types, _get_type_to_gather(field_type))
        end
    end
    return nothing
end

function _get_type_to_gather(input_type::Type)
    if _is_nothing_union(input_type)
        type_to_gather = _get_optional_type(input_type)
    elseif input_type <: AbstractArray
        type_to_gather = eltype(input_type)
    else
        type_to_gather = input_type
    end
    return type_to_gather
end

end
