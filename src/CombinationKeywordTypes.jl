"""
    AllOf{T}

Type introduced for generating the JSON schema `allOf` keyword.

Can be added to `combinationkeywords` for some Struct to add the keyword to the generated schema of that struct,
    or chained with other keywords.

# Example
```julia
combinationkeywords(MyStructType) = (AllOf{StructTypeA, StructTypeB}, Not{AllOf{StructTypeC, StructTypeD}})
```
"""
struct AllOf{T,S} end

"""
    AnyOf{T}

Type introduced for generating the JSON schema `anyOf` keyword.

Can be added to `combinationkeywords` for some Struct to add the keyword to the generated schema of that struct,
    or chained with other keywords.

# Example
```julia
combinationkeywords(MyStructType) = (AnyOf{StructTypeA, StructTypeB}, Not{AnyOf{StructTypeC, StructTypeD}})
```
"""
struct AnyOf{T,S} end

"""
    OneOf{T}

Type introduced for generating the JSON schema `oneOf` keyword.

Can be added to `combinationkeywords` for some Struct to add the keyword to the generated schema of that struct,
    or chained with other keywords.

# Example
```julia
combinationkeywords(MyStructType) = (OneOf{StructTypeA, StructTypeB}, Not{OneOf{StructTypeC, StructTypeD}})
```
"""
struct OneOf{T,S} end

"""
    Not{T}

Type introduced for generating the JSON schema `not` keyword.

Can be added to `combinationkeywords` for some Struct to add the keyword to the generated schema of that struct,
    or chained with other keywords.

# Example
```julia
combinationkeywords(MyStructType) = (Not{StructA}, AnyOf{Not{StructB}, StructC})
```
"""
struct Not{T} end

"""
    combinationkeywords(T::Type)::Tuple

Specifies which JSON boolean combination keywords will be included in the generated schema for a type.

Elements should be one of the following types: `AllOf{T,S}`, `AnyOf{T,S}`, `OneOf{T,S}`, `Not{T}`.

# Example
```julia
combinationkeywords(MyStructType) = (AllOf{SchemaA, SchemaB}, Not{SchemaC})
```
"""
function combinationkeywords end

combinationkeywords(::Type) = ()