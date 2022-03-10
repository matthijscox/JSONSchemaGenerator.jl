# JSONSchemaGenerator

Create minimal JSON schemas from custom Julia types.

Current restrictions:
* no parametric types
* no Union types, except `Union{Nothing, T}` for optional fields
* must use `StructTypes.StructType` definition for your custom types
