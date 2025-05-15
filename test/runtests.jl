using JSONSchemaGenerator
using Test
using Dates
using JSON
using JSON3
using JSONSchema
using StructTypes

module TestTypes
    using Dates
    using StructTypes
    import JSONSchemaGenerator
    const JSG = JSONSchemaGenerator

    struct BasicSchema
        int::Int64
        float::Float64
        string::String
        symbol::Symbol
        char::Char
        uuid::Base.UUID
        timetype::Dates.DateTime
        version_number::VersionNumber
        regex::Regex
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

    struct ArraySchema
        integers::Vector{Int64}
        types::Vector{OptionalFieldSchema}
    end
    StructTypes.StructType(::Type{ArraySchema}) = StructTypes.Struct()

    function ArraySchema()
        optional_array = [
            TestTypes.OptionalFieldSchema(1, "foo"),
            TestTypes.OptionalFieldSchema(1, nothing)
        ]
        return ArraySchema([1,2], optional_array)
    end

    struct NestedSchema
        int::Int
        optional::OptionalFieldSchema
        enum::EnumeratedSchema
    end
    StructTypes.StructType(::Type{NestedSchema}) = StructTypes.Struct()

    function NestedSchema()
        return NestedSchema(
            1,
            OptionalFieldSchema(1, nothing),
            EnumeratedSchema(apple)
        )
    end

    struct DoubleNestedSchema
        int::Int
        arrays::ArraySchema
        enum::EnumeratedSchema
        nested::NestedSchema
    end
    StructTypes.StructType(::Type{DoubleNestedSchema}) = StructTypes.Struct()

    function DoubleNestedSchema()
        return DoubleNestedSchema(
            1,
            ArraySchema(),
            EnumeratedSchema(apple),
            NestedSchema(),
        )
    end

    struct ConstantInt1Schema
        int::Val{1}
    end
    struct ConstantInt2Schema
        int::Val{2}
    end
    struct ConstantBoolTrueSchema
        bool::Val{true}
    end
    struct BooleanCombinationSchema
        int::Int
        bool::Bool
    end
    JSG.combinationkeywords(::Type{BooleanCombinationSchema}) = [
        JSG.AllOf{
            JSG.AnyOf{ConstantInt1Schema, ConstantInt2Schema},
            JSG.Not{ConstantBoolTrueSchema}
        }
    ]
    StructTypes.StructType(::Type{BooleanCombinationSchema}) = StructTypes.Struct()

    struct BadBooleanCombinationSchema
        int::Int
    end
    StructTypes.StructType(::Type{BadBooleanCombinationSchema}) = StructTypes.Struct()
    JSG.combinationkeywords(::Type{BadBooleanCombinationSchema}) = [
        JSG.AllOf{ConstantInt1Schema, ConstantInt1Schema},
        JSG.AllOf{ConstantInt2Schema, ConstantInt2Schema}
    ]

    struct BadBooleanCombinationSchema2
        int::Int
    end
    StructTypes.StructType(::Type{BadBooleanCombinationSchema2}) = StructTypes.Struct()
    JSG.combinationkeywords(::Type{BadBooleanCombinationSchema2}) = [Int32]
end

function test_json_schema_validation(obj::T) where T
    json_schema = JSONSchemaGenerator.schema(T)
    test_json_schema_validation(json_schema, obj)
end

function test_json_schema_validation(json_schema, obj)
    my_schema = JSONSchema.Schema(json_schema) # make a schema
    json_string = JSON3.write(obj) # we can write the schema to a JSON string
    @test JSONSchema.validate(my_schema, JSON.parse(json_string)) === nothing # validation is OK
end

@testset "Basic Types" begin
    json_schema = JSONSchemaGenerator.schema(TestTypes.BasicSchema)
    @test json_schema["type"] == "object"
    object_properties = ["int", "float", "string", "symbol", "char", "uuid", "timetype", "version_number", "regex"]
    @test all(x in object_properties for x in json_schema["required"])
    @test all(x in object_properties for x in keys(json_schema["properties"]))

    @test json_schema["properties"]["int"]["type"] == "integer"
    @test json_schema["properties"]["float"]["type"] == "number"
    @test json_schema["properties"]["string"]["type"] == "string"
    @test json_schema["properties"]["symbol"]["type"] == "string"
    @test json_schema["properties"]["char"]["type"] == "string"
    @test json_schema["properties"]["uuid"]["type"] == "string"
    @test json_schema["properties"]["timetype"]["type"] == "string"
    @test json_schema["properties"]["version_number"]["type"] == "string"
    @test json_schema["properties"]["regex"]["type"] == "string"

    test_json_schema_validation(TestTypes.BasicSchema(1, 1.0, "a", :b, 'c', Base.UUID(0), Dates.now(), v"0.0.1", r""))
end

@testset "Enumerators" begin
    json_schema = JSONSchemaGenerator.schema(TestTypes.EnumeratedSchema)
    enum_instances = ["apple", "orange"]
    fruit_json_enum = json_schema["properties"]["fruit"]["enum"]
    @test all(x in fruit_json_enum for x in enum_instances)

    test_json_schema_validation(TestTypes.EnumeratedSchema(TestTypes.apple))
end

@testset "Optional Fields" begin
    json_schema = JSONSchemaGenerator.schema(TestTypes.OptionalFieldSchema)
    @test !("optional" in json_schema["required"])
    @test json_schema["required"] == ["int"]
    @test json_schema["properties"]["optional"]["type"] == "string"

    # and the JSONSchema validation works fine
    test_json_schema_validation(TestTypes.OptionalFieldSchema(1, nothing))
    test_json_schema_validation(TestTypes.OptionalFieldSchema(1, "foo"))

    #StructTypes.StructType(::Type{TestTypes.OptionalFieldSchema}) = StructTypes.Struct()
    # if StructType is defined, but omitempties is not defined for the optional field, then we should throw an error
    #@test_throws OmitEmptiesException json_schema = JSONSchemaGenerator.schema(TestTypes.OptionalFieldSchema)
    #StructTypes.omitempties(::Type{TestTypes.OptionalFieldSchema}) = (:optional,)
    #json_schema = JSONSchemaGenerator.schema(TestTypes.OptionalFieldSchema)
end

@testset "Arrays" begin
    #=
        {
    "type": "array",
    "items": {
        "type": "object" # or "type": { "\$ref": "#/OptionalFieldSchema" }
    }
    }=#
    json_schema = JSONSchemaGenerator.schema(TestTypes.ArraySchema)
    # so behavior depends on the eltype of the array
    @test json_schema["properties"]["integers"]["type"] == "array"
    @test json_schema["properties"]["integers"]["items"]["type"] == "integer"

    opt_schema = JSONSchemaGenerator.schema(TestTypes.OptionalFieldSchema)
    @test json_schema["properties"]["types"]["items"] == opt_schema

    test_json_schema_validation(TestTypes.ArraySchema())
end

@testset "Nested Structs" begin
    nested_schema = JSONSchemaGenerator.schema(TestTypes.NestedSchema)
    optional_field_schema = JSONSchemaGenerator.schema(TestTypes.OptionalFieldSchema)
    # by default it's a nested JSON schema
    @test nested_schema["properties"]["optional"] == optional_field_schema

    test_json_schema_validation(TestTypes.NestedSchema())

    double_nested_schema = JSONSchemaGenerator.schema(TestTypes.DoubleNestedSchema)
    @test double_nested_schema["properties"]["nested"] == nested_schema

    test_json_schema_validation(TestTypes.DoubleNestedSchema())
end

@testset "StructTypes.DataType gathering" begin
    types = JSONSchemaGenerator._gather_data_types(TestTypes.NestedSchema)
    expected_types = [
        TestTypes.OptionalFieldSchema
        TestTypes.EnumeratedSchema
    ]
    @test length(types) == length(expected_types)
    @test all(x in types for x in expected_types)

    types = JSONSchemaGenerator._gather_data_types(TestTypes.ArraySchema)
    expected_types = [
        TestTypes.OptionalFieldSchema
    ]
    @test length(types) == length(expected_types)
    @test all(x in types for x in expected_types)

    types = JSONSchemaGenerator._gather_data_types(TestTypes.DoubleNestedSchema)
    expected_types = [
        TestTypes.NestedSchema
        TestTypes.EnumeratedSchema
        TestTypes.OptionalFieldSchema
        TestTypes.ArraySchema
    ]
    @test length(types) == length(expected_types)
    @test all(x in types for x in expected_types)
end

@testset "Nested Structs using schema references" begin

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

    json_schema = JSONSchemaGenerator.schema(TestTypes.DoubleNestedSchema, use_references=true)

    array_ref = json_schema["properties"]["arrays"]["\$ref"]
    @test startswith(array_ref, "#/\$defs/")
    type_name = split(array_ref, "#/\$defs/")[2]
    @test type_name == string(TestTypes.ArraySchema)

    @test length(json_schema["\$defs"]) == length(JSONSchemaGenerator._gather_data_types(TestTypes.DoubleNestedSchema))
    array_type_def = json_schema["\$defs"][string(TestTypes.ArraySchema)]
    array_optional_eltype = array_type_def["properties"]["types"]["items"]
    # this must also be a reference
    @test array_optional_eltype["\$ref"] == "#/\$defs/$(string(TestTypes.OptionalFieldSchema))"

    nested_def = json_schema["\$defs"][string(TestTypes.NestedSchema)]
    @test nested_def["properties"]["optional"]["\$ref"] == "#/\$defs/" * string(TestTypes.OptionalFieldSchema)

    # https://www.jsonschemavalidator.net/ succeeds, but JSONSchema fails to resolve references
    test_json_schema_validation(json_schema, TestTypes.DoubleNestedSchema())

    # also for single nesting
    json_schema = JSONSchemaGenerator.schema(TestTypes.NestedSchema, use_references=true, dict_type=Dict)
    test_json_schema_validation(json_schema, TestTypes.NestedSchema())
end

@testset "Boolean Combination of Schemas" begin
    @testset "Good weather" begin
        combo_schema = JSONSchemaGenerator.schema(TestTypes.BooleanCombinationSchema)
        constantint1_schema = JSONSchemaGenerator.schema(TestTypes.ConstantInt1Schema)
        constantint2_schema = JSONSchemaGenerator.schema(TestTypes.ConstantInt2Schema)
        constantbooltrue_schema = JSONSchemaGenerator.schema(TestTypes.ConstantBoolTrueSchema)

        @test combo_schema["allOf"][1]["anyOf"][1] == constantint1_schema
        @test combo_schema["allOf"][1]["anyOf"][2] == constantint2_schema
        @test combo_schema["allOf"][2]["not"] == constantbooltrue_schema

        test_json_schema_validation(TestTypes.BooleanCombinationSchema(1, false))
    end

    @testset "Multiple uses of same keyword in one object" begin
        @test_throws Exception bad_combo_schema = JSONSchemaGenerator.schema(TestTypes.BadBooleanCombinationSchema)
    end

    @testset "Use of incorrect type in combinationkeywords" begin
        @test_throws Exception bad_combo_schema2 = JSONSchemaGenerator.schema(TestTypes.BadBooleanCombinationSchema2)
    end
end
