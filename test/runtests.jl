using JSONSchemaGenerator
using Test
using JSON
using JSON3
using JSONSchema
using StructTypes

module TestTypes
    using StructTypes

    struct BasicSchema
        int::Int64
        float::Float64
        string::String
    end
    StructTypes.StructType(::Type{BasicSchema}) = StructTypes.Struct()

    @enum Fruit begin
        apple = 1
        orange = 2
    end
    struct EnumeratedSchema
        fruit::Fruit
    end
    StructTypes.StructType(::Type{EnumeratedSchema}) = StructTypes.Struct()

    struct OptionalFieldSchema
        int::Int
        optional::Union{Nothing, String}
    end
    StructTypes.StructType(::Type{OptionalFieldSchema}) = StructTypes.Struct()
    StructTypes.omitempties(::Type{OptionalFieldSchema}) = (:optional,)

    struct NestedSchema
        int::Int
        optional::OptionalFieldSchema
        enum::EnumeratedSchema
    end
    StructTypes.StructType(::Type{NestedSchema}) = StructTypes.Struct()

    struct DoubleNestedSchema
        int::Int
        optional::OptionalFieldSchema
        enum::EnumeratedSchema
        nested::NestedSchema
    end
    StructTypes.StructType(::Type{DoubleNestedSchema}) = StructTypes.Struct()

    struct ArraySchema
        integers::Vector{Int64}
        types::Vector{EnumeratedSchema}
    end
    StructTypes.StructType(::Type{ArraySchema}) = StructTypes.Struct()

end

@testset "Basic Types" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.BasicSchema)
    @test json_schema["type"] == "object"
    object_properties = ["int", "float", "string"]
    @test all(x in object_properties for x in json_schema["required"])
    @test all(x in object_properties for x in keys(json_schema["properties"]))

    @test json_schema["properties"]["int"]["type"] == "integer"
    @test json_schema["properties"]["float"]["type"] == "number"
    @test json_schema["properties"]["string"]["type"] == "string"
    # can be written to a JSON file
    json_string = JSON3.write(TestTypes.BasicSchema(1, 1.0, "a"))
    # and the JSONSchema validation works fine
    my_schema = Schema(json_schema)
    @test validate(my_schema, JSON.parse(json_string)) === nothing
end

@testset "Enumerators" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.EnumeratedSchema)
    enum_instances = ["apple", "orange"]
    fruit_json_enum = json_schema["properties"]["fruit"]["enum"]
    @test all(x in fruit_json_enum for x in enum_instances)
end

@testset "Optional Fields" begin
    json_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)
    @test !("optional" in json_schema["required"])
    @test json_schema["required"] == ["int"]
    @test json_schema["properties"]["optional"]["type"] == "string"

    # and the JSONSchema validation works fine
    obj = TestTypes.OptionalFieldSchema(1, nothing)
    json_string = JSON3.write(obj)
    my_schema = Schema(json_schema)
    @test validate(my_schema, JSON.parse(json_string)) === nothing

    # and the JSONSchema validation works fine
    obj = TestTypes.OptionalFieldSchema(1, "foo")
    json_string = JSON3.write(obj)
    my_schema = Schema(json_schema)
    @test validate(my_schema, JSON.parse(json_string)) === nothing

    #StructTypes.StructType(::Type{TestTypes.OptionalFieldSchema}) = StructTypes.Struct()
    # if StructType is defined, but omitempties is not defined for the optional field, then we should throw an error
    #@test_throws OmitEmptiesException json_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)
    #StructTypes.omitempties(::Type{TestTypes.OptionalFieldSchema}) = (:optional,)
    #json_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)
end

@testset "Nested Structs" begin
    nested_schema = JSONSchemaGenerator.generate(TestTypes.NestedSchema)
    optional_field_schema = JSONSchemaGenerator.generate(TestTypes.OptionalFieldSchema)
    # by default it's a nested JSON schema
    @test nested_schema["properties"]["optional"] == optional_field_schema

    double_nested_schema = JSONSchemaGenerator.generate(TestTypes.DoubleNestedSchema)
    @test double_nested_schema["properties"]["nested"] == nested_schema

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
    #=
        {
    "type": "array",
    "items": {
        "type": "object" # or "type": { "\$ref": "#/OptionalFieldSchema" }
    }
    }=#
    json_schema = JSONSchemaGenerator.generate(TestTypes.ArraySchema)
    # so behavior depends on the eltype of the array
    @test json_schema["properties"]["integers"]["type"] == "array"
    @test json_schema["properties"]["integers"]["items"]["type"] == "integer"

    enum_schema = JSONSchemaGenerator.generate(TestTypes.EnumeratedSchema)
    @test json_schema["properties"]["types"]["items"] == enum_schema
end
