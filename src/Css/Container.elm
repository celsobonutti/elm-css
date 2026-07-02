module Css.Container exposing
    ( Condition
    , withContainer, withContainerNamed, withContainerQuery
    , anyOf, allOf, not, rawCondition
    , minWidth, maxWidth, minHeight, maxHeight
    , minInlineSize, maxInlineSize, minBlockSize, maxBlockSize
    , minAspectRatio, maxAspectRatio
    , width, height, inlineSize, blockSize, aspectRatio
    , gt, lt, ge, le, eq, between
    , Ratio, ratio
    , orientation, Landscape, Portrait, landscape, portrait
    , ContainerTypeValue, containerType, normal, size
    , containerName, containerNames, container
    , toStructureCondition
    )

{-| Functions for building [`@container` queries](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@container)
and the container establishment properties.


# Data Structures

@docs Condition


# `@container` rule constructors

@docs withContainer, withContainerNamed, withContainerQuery


# Combinators

@docs anyOf, allOf, not, rawCondition


# Size features

@docs minWidth, maxWidth, minHeight, maxHeight
@docs minInlineSize, maxInlineSize, minBlockSize, maxBlockSize
@docs minAspectRatio, maxAspectRatio


# Range-syntax feature tokens

@docs width, height, inlineSize, blockSize, aspectRatio
@docs gt, lt, ge, le, eq, between
@docs Ratio, ratio


# Orientation

@docs orientation, Landscape, Portrait, landscape, portrait


# Establishment properties

@docs ContainerTypeValue, containerType, normal, size
@docs containerName, containerNames, container


# Internal

@docs toStructureCondition

-}

import Css exposing (Style)
import Css.Preprocess as Preprocess
import Css.Structure as Structure exposing (Compatible(..))


{-| An opaque container query condition. Build with the feature functions and
combine with `anyOf`/`allOf`/`not`.
-}
type Condition
    = Condition (Structure.QueryCondition Structure.ContainerFeature)


unwrap : Condition -> Structure.QueryCondition Structure.ContainerFeature
unwrap (Condition c) =
    c


type alias AbsoluteLength compatible =
    { compatible | value : String, absoluteLength : Compatible }


type alias Value compatible =
    { compatible | value : String }


{-| Attach a container query to a set of styles. The `Condition`s in the list
are combined with `and` at the top level.

    withContainer [ minWidth (px 400) ] [ Css.color (hex "000000") ]

-}
withContainer : List Condition -> List Style -> Style
withContainer conditions =
    Preprocess.WithContainer Nothing (combineAnd conditions)


{-| Like `withContainer`, but scoped to a named container.

    withContainerNamed "sidebar" [ minWidth (px 400) ] [ Css.color (hex "000000") ]

-}
withContainerNamed : String -> List Condition -> List Style -> Style
withContainerNamed name conditions =
    Preprocess.WithContainer (Just name) (combineAnd conditions)


{-| Escape hatch: pass a raw container-query string (optionally including a
container name) verbatim.

    withContainerQuery "sidebar (min-width: 400px)" [ Css.color (hex "000000") ]

-}
withContainerQuery : String -> List Style -> Style
withContainerQuery raw =
    Preprocess.WithContainer Nothing (Structure.Raw raw)


combineAnd : List Condition -> Structure.QueryCondition Structure.ContainerFeature
combineAnd conditions =
    case List.map unwrap conditions of
        only :: [] ->
            only

        many ->
            Structure.And many


{-| Internal-use helper for `Css.Global.container`. Converts a list of
conditions (joined with `and`) into the underlying structure condition.
-}
toStructureCondition : List Condition -> Structure.QueryCondition Structure.ContainerFeature
toStructureCondition =
    combineAnd


{-| Match if any of the given conditions match.
-}
anyOf : List Condition -> Condition
anyOf conditions =
    Condition (Structure.Or (List.map unwrap conditions))


{-| Match if all of the given conditions match.
-}
allOf : List Condition -> Condition
allOf conditions =
    Condition (Structure.And (List.map unwrap conditions))


{-| Negate a condition.
-}
not : Condition -> Condition
not condition =
    Condition (Structure.Not (unwrap condition))


{-| Escape hatch: pass a raw condition string verbatim, e.g. for
`style()`/`scroll-state()` container queries not otherwise supported.
-}
rawCondition : String -> Condition
rawCondition raw =
    Condition (Structure.Raw raw)


feature : String -> Value compatible -> Condition
feature key { value } =
    Condition (Structure.Feature { feature = key, value = Just value })


{-| Container feature `min-width`.
-}
minWidth : AbsoluteLength compatible -> Condition
minWidth value =
    feature "min-width" value


{-| Container feature `max-width`.
-}
maxWidth : AbsoluteLength compatible -> Condition
maxWidth value =
    feature "max-width" value


{-| Container feature `min-height`.
-}
minHeight : AbsoluteLength compatible -> Condition
minHeight value =
    feature "min-height" value


{-| Container feature `max-height`.
-}
maxHeight : AbsoluteLength compatible -> Condition
maxHeight value =
    feature "max-height" value


{-| Container feature `min-inline-size`.
-}
minInlineSize : AbsoluteLength compatible -> Condition
minInlineSize value =
    feature "min-inline-size" value


{-| Container feature `max-inline-size`.
-}
maxInlineSize : AbsoluteLength compatible -> Condition
maxInlineSize value =
    feature "max-inline-size" value


{-| Container feature `min-block-size`.
-}
minBlockSize : AbsoluteLength compatible -> Condition
minBlockSize value =
    feature "min-block-size" value


{-| Container feature `max-block-size`.
-}
maxBlockSize : AbsoluteLength compatible -> Condition
maxBlockSize value =
    feature "max-block-size" value


{-| Container feature `min-aspect-ratio`.
-}
minAspectRatio : Ratio -> Condition
minAspectRatio value =
    feature "min-aspect-ratio" value


{-| Container feature `max-aspect-ratio`.
-}
maxAspectRatio : Ratio -> Condition
maxAspectRatio value =
    feature "max-aspect-ratio" value


{-| An aspect ratio, e.g. `ratio 16 9`. Structurally identical to `Css.Media.Ratio`.
-}
type alias Ratio =
    { value : String, ratio : Compatible }


{-| Create a ratio.

    ratio 16 9

-}
ratio : Int -> Int -> Ratio
ratio numerator denominator =
    { value = String.fromInt numerator ++ "/" ++ String.fromInt denominator, ratio = Compatible }


type alias Orientation a =
    { a | value : String, orientation : Compatible }


{-| -}
type alias Landscape =
    { value : String, orientation : Compatible }


{-| -}
type alias Portrait =
    { value : String, orientation : Compatible }


{-| -}
landscape : Landscape
landscape =
    { value = "landscape", orientation = Compatible }


{-| -}
portrait : Portrait
portrait =
    { value = "portrait", orientation = Compatible }


{-| Container feature `orientation`. Accepts `landscape` or `portrait`.
-}
orientation : Orientation a -> Condition
orientation value =
    feature "orientation" value


{-| -}
width : { value : String, containerFeature : Compatible, mediaFeature : Compatible }
width =
    { value = "width", containerFeature = Compatible, mediaFeature = Compatible }


{-| -}
height : { value : String, containerFeature : Compatible, mediaFeature : Compatible }
height =
    { value = "height", containerFeature = Compatible, mediaFeature = Compatible }


{-| -}
aspectRatio : { value : String, containerFeature : Compatible, mediaFeature : Compatible }
aspectRatio =
    { value = "aspect-ratio", containerFeature = Compatible, mediaFeature = Compatible }


{-| Container-only feature token; also usable as a `container-type` value.
-}
inlineSize : { value : String, containerFeature : Compatible, containerTypeValue : Compatible }
inlineSize =
    { value = "inline-size", containerFeature = Compatible, containerTypeValue = Compatible }


{-| Container-only feature token.
-}
blockSize : { value : String, containerFeature : Compatible }
blockSize =
    { value = "block-size", containerFeature = Compatible }


type alias FeatureToken f =
    { f | value : String, containerFeature : Compatible }


rangeCondition : Structure.Comparison -> Value compatible -> FeatureToken f -> Condition
rangeCondition comparison val token =
    Condition
        (Structure.Range
            { feature = token.value
            , lower = Just ( comparison, val.value )
            , upper = Nothing
            }
        )


{-| `feature > value`
-}
gt : Value compatible -> FeatureToken f -> Condition
gt =
    rangeCondition Structure.Gt


{-| `feature < value`
-}
lt : Value compatible -> FeatureToken f -> Condition
lt =
    rangeCondition Structure.Lt


{-| `feature >= value`
-}
ge : Value compatible -> FeatureToken f -> Condition
ge =
    rangeCondition Structure.Ge


{-| `feature <= value`
-}
le : Value compatible -> FeatureToken f -> Condition
le =
    rangeCondition Structure.Le


{-| `feature = value`
-}
eq : Value compatible -> FeatureToken f -> Condition
eq =
    rangeCondition Structure.Eq


{-| `low <= feature <= high`
-}
between : Value compatibleLow -> Value compatibleHigh -> FeatureToken f -> Condition
between low high token =
    Condition
        (Structure.Range
            { feature = token.value
            , lower = Just ( Structure.Le, low.value )
            , upper = Just ( Structure.Le, high.value )
            }
        )


{-| A value for the `container-type` property.
-}
type alias ContainerTypeValue a =
    { a | value : String, containerTypeValue : Compatible }


{-| `container-type: normal`
-}
normal : { value : String, containerTypeValue : Compatible }
normal =
    { value = "normal", containerTypeValue = Compatible }


{-| `container-type: size`
-}
size : { value : String, containerTypeValue : Compatible }
size =
    { value = "size", containerTypeValue = Compatible }


{-| The [`container-type`](https://developer.mozilla.org/en-US/docs/Web/CSS/container-type) property.

    containerType size

    containerType inlineSize

    containerType normal

-}
containerType : ContainerTypeValue a -> Style
containerType value =
    Css.property "container-type" value.value


{-| The [`container-name`](https://developer.mozilla.org/en-US/docs/Web/CSS/container-name) property.
-}
containerName : String -> Style
containerName name =
    Css.property "container-name" name


{-| Set multiple container names.

    containerNames [ "sidebar", "layout" ] -- container-name: sidebar layout

-}
containerNames : List String -> Style
containerNames names =
    Css.property "container-name" (String.join " " names)


{-| The [`container`](https://developer.mozilla.org/en-US/docs/Web/CSS/container) shorthand.

    container "sidebar" inlineSize -- container: sidebar / inline-size

-}
container : String -> ContainerTypeValue a -> Style
container name typeValue =
    Css.property "container" (name ++ " / " ++ typeValue.value)
