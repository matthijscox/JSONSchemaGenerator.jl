module JSONSchemaGenerator

import Dates
import OrderedCollections: OrderedDict
import StructTypes

if !isdefined(Base, :fieldtypes) && VERSION < v"1.1"
    fieldtypes(T::Type) = (Any[fieldtype(T, i) for i in 1:fieldcount(T)]...,)
end

include("CombinationKeywordTypes.jl")

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
_json_type(::Type{Symbol}) = :string
_json_type(::Type{<:AbstractChar}) = :string
_json_type(::Type{Base.UUID}) = :string
_json_type(::Type{T}) where {T <: Dates.TimeType} = :string
_json_type(::Type{VersionNumber}) = :string
_json_type(::Type{Base.Regex}) = :string
_json_type(::Type{<:Val}) = :const
_json_type(::Type{<:Tuple}) = :enum
_json_type(::Type{<:AllOf}) = :keyword
_json_type(::Type{<:AnyOf}) = :keyword
_json_type(::Type{<:OneOf}) = :keyword
_json_type(::Type{<:Not}) = :keyword

_is_nothing_union(::Type) = false
_is_nothing_union(::Type{Nothing}) = false
_is_nothing_union(::Type{Union{Nothing, T}}) where T = true

_get_optional_type(::Type{Union{Nothing, T}}) where T = T

Base.@kwdef mutable struct SchemaSettings
    toplevel::Bool = true # will be set to false by top level schema object
    use_references::Bool = false # create schema references instead of nesting types
    reference_types::Set{DataType}
    reference_path = "#/\$defs/"
    dict_type::Type{<:AbstractDict} = OrderedDict
end

"""
```julia
schema(
    schema_type::Type;
    use_references::Bool = false,
    dict_type::Type{<:AbstractDict} = OrderedCollections.OrderedDict
)::AbstractDict{String, Any}
```

Generate a JSONSchema in the form of a dictionary.

# Example
```julia
using JSONSchemaGenerator, StructTypes

struct OptionalFieldSchema
    int::Int
    optional::Union{Nothing, String}
end
StructTypes.StructType(::Type{OptionalFieldSchema}) = StructTypes.Struct()
StructTypes.omitempties(::Type{OptionalFieldSchema}) = (:optional,)

struct NestedFieldSchema
    int::Int
    field::OptionalFieldSchema
    vector::Vector{OptionalFieldSchema}
end
StructTypes.StructType(::Type{NestedFieldSchema}) = StructTypes.Struct()

schema_dict = JSONSchemaGenerator.schema(NestedFieldSchema)
```
"""
function schema(
    schema_type::Type;
    use_references::Bool = false,
    dict_type::Type{<:AbstractDict} = OrderedDict
)::AbstractDict{String, Any}
    if use_references
        reference_types = _gather_data_types(schema_type)
    else
        reference_types = Set{DataType}()
    end
    settings = SchemaSettings(
        use_references = use_references,
        reference_types = reference_types,
        dict_type = dict_type,
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
    optional_fields = StructTypes.omitempties(julia_type)
    # TODO: use StructTypes.names instead of fieldnames
    for (name, type) in zip(names, types)
        name_string = string(name)
        if _is_nothing_union(type) # we assume it's an optional field type
            @assert name in optional_fields "we miss $name in $(StructTypes.omitempties(julia_type))"
            type = _get_optional_type(type)
        elseif !(name in optional_fields)
            push!(required_json_property_names, name_string)
        end
        if settings.use_references && type in settings.reference_types
            push!(json_properties, _json_reference(type, settings))
        else
            push!(json_properties, _generate_json_type_def(type, settings))
        end
        push!(json_property_names, name_string)
    end
    d = settings.dict_type{String, Any}(
        "type" => "object",
        "properties" => settings.dict_type{String, Any}(
            json_property_names .=> json_properties
        ),
        "required" => required_json_property_names,
    )
    if is_top_level && settings.use_references
        d["\$defs"] = _generate_json_reference_types(settings)
    end
    for combination_type in combinationkeywords(julia_type)
        _json_type(combination_type) == :keyword ? nothing : error("combinationkeywords($julia_type) should only contain valid keywords")
        keyword_dict = _generate_json_type_def(combination_type, settings)
        issubset(keys(keyword_dict), keys(d)) ? error("each keyword should only appear at most once in combinationkeywords($julia_type)") : nothing
        merge!(d, keyword_dict)
    end
    return d
end

function _generate_json_type_def(julia_type::Type, settings::SchemaSettings)
    return _generate_json_type_def(Val(_json_type(julia_type)), julia_type, settings)
end

function _generate_json_type_def(::Val{:object}, julia_type::Type, settings::SchemaSettings)
    return _generate_json_object(julia_type, settings)
end

function _generate_json_type_def(::Val{:array}, julia_type::Type{<:AbstractArray}, settings::SchemaSettings)
    element_type = eltype(julia_type)
    if settings.use_references && element_type in settings.reference_types
        item_type = _json_reference(element_type, settings)
    else
        item_type = _generate_json_type_def(element_type, settings)
    end
    return settings.dict_type{String, Any}(
        "type" => "array",
        "items" => item_type
    )
end

function _generate_json_type_def(::Val{:const}, julia_type::Type{<:Val}, settings::SchemaSettings)
    return settings.dict_type{String, Any}(
        "const" => julia_type.parameters[1]
    )
end

function _generate_json_type_def(::Val{:enum}, julia_type::Type{<:Tuple}, settings::SchemaSettings)
    return settings.dict_type{String, Any}(
        "enum" => [p isa Symbol ? String(p) : p for p in julia_type.parameters]
    )
end

function _generate_json_type_def(::Val{:enum}, julia_type::Type, settings::SchemaSettings)
    return settings.dict_type{String, Any}(
        "enum" => string.(instances(julia_type))
    )
end

function _generate_json_type_def(::Val{:keyword}, julia_type::Type{AllOf{T,S}}, settings::SchemaSettings) where {T,S}
    return settings.dict_type{String, Any}(
        "allOf" => [_generate_json_type_def(T, settings), _generate_json_type_def(S, settings)]
    )
end

function _generate_json_type_def(::Val{:keyword}, julia_type::Type{AnyOf{T,S}}, settings::SchemaSettings) where {T,S}
    return settings.dict_type{String, Any}(
        "anyOf" => [_generate_json_type_def(T, settings), _generate_json_type_def(S, settings)]
    )
end

function _generate_json_type_def(::Val{:keyword}, julia_type::Type{OneOf{T,S}}, settings::SchemaSettings) where {T,S}
    return settings.dict_type{String, Any}(
        "oneOf" => [_generate_json_type_def(T, settings), _generate_json_type_def(S, settings)]
    )
end

function _generate_json_type_def(::Val{:keyword}, julia_type::Type{Not{T}}, settings::SchemaSettings) where {T}
    return settings.dict_type{String, Any}(
        "not" => _generate_json_type_def(T, settings)
    )
end

function _generate_json_type_def(::Val, julia_type::Type, settings::SchemaSettings)
    return settings.dict_type{String, Any}(
        "type" => string(_json_type(julia_type))
    )
end

# used in things like { "\$ref": "#/MyObject" }
function _json_reference(julia_type::Type, settings::SchemaSettings)
    return settings.dict_type{String, Any}(
         "\$ref" => settings.reference_path * string(julia_type)
    )
end

function _generate_json_reference_types(settings::SchemaSettings)
    d = settings.dict_type{String, Any}()
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
