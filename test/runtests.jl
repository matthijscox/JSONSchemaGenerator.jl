using JSONSchemaGenerator
using Test
using JSON3
using JSONSchema
using StructTypes

module TestTypes

    struct BasicSchema
        int::Int64
        float::Float64
        string::String
    end

    @enum Fruit begin
        apple = 1
        orange = 2
    end
    struct EnumeratedSchema
        fruit::Fruit
    end

    struct OptionalFieldSchema
        int::Int
        optional::Union{Nothing, String}
    end

    struct NestedSchema
        int::Int
        optional::OptionalFieldSchema
        enum::EnumeratedSchema
    end

    struct DoubleNestedSchema
        int::Int
        optional::OptionalFieldSchema
        enum::EnumeratedSchema
        nested::NestedSchema
    end

    struct ArraySchema
        integers::Vector{Int64}
        types::Vector{EnumeratedSchema}
    end

end

@testset "Basic Types" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.BasicSchema)
    # is a dictionary that can be passed into JSONSchema.Schema()
    # and can be written to a JSON file
end

@testset "Enumerators" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.EnumeratedSchema)
end

@testset "Optional Fields" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)

    StructTypes.StructType(::Type{TestTypes.OptionalFieldSchema}) = StructTypes.Struct()
    # if StructType is defined, but omitempties is not defined for the optional field, then we should throw an error
    #@test_throws OmitEmptiesException json_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)
    StructTypes.omitempties(::Type{TestTypes.OptionalFieldSchema}) = (:optional,)
    json_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)
end

@testset "Nested Structs" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.DoubleNestedSchema)
    # now, for readability we want to make use of JSON schema references
    # it should resolve to something like this:
    """
    {
    "type": "object",
    "properties": {
        "int": { "type": "integer" },
        "optional": { "\$ref": "#/\$defs/OptionalFieldSchema" },
        "enum": { "\$ref": "#/\$defs/EnumeratedSchema" },
        "nested": { "\$ref": "#/\$defs/NestedSchema" }
    },
    "required": ["int", "optional", "enum", "nested"],

    "\$defs": {
        "NestedSchema": {
            "type": "object",
            "properties": {
                "int": { "type": "integer" },
                "optional": { "\$ref": "#/OptionalFieldSchema" },
                "enum": { "\$ref": "#/EnumeratedSchema" }
            },
            "required": ["int", "optional", "enum"],
        },
        "OptionalFieldSchema": {
            "type": "object",
            "properties": {
                "int": { "type": "integer" },
                "optional": { "type": "string" }
            },
            "required": ["int"],
        },
        "EnumeratedSchema": {
            "type": "object",
            "properties": {
                "fruit": { "enum": ["apple", "orange"] },
            },
            "required": ["fruit"],
        }
    }
    """
end

@testset "Arrays" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.ArraySchema)
end
