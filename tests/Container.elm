module Container exposing (outputContainerRule, outputConditionForms, outputRangeForms, outputConditionQuery)

import Css.Structure as Structure exposing (..)
import Css.Structure.Output exposing (prettyPrint)
import Expect
import Test exposing (Test, describe, test)
import TestUtil exposing (outdented)


sampleBlock : StyleBlock
sampleBlock =
    StyleBlock
        (Selector (TypeSelectorSequence (TypeSelector "p") []) [] Nothing)
        []
        [ Property "color:#FF0000" ]


sheet : List Declaration -> Structure.Stylesheet
sheet declarations =
    { charset = Nothing, imports = [], namespaces = [], declarations = declarations }


feat : String -> Maybe String -> QueryCondition ContainerFeature
feat name value =
    Feature { feature = name, value = value }


outputContainerRule : Test
outputContainerRule =
    describe "@container rule emission"
        [ test "anonymous, single feature" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (feat "min-width" (Just "400px")) [ sampleBlock ] ])
                    |> Expect.equal "@container (min-width: 400px){p{color:#FF0000;}}"
        , test "named container" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule (Just "sidebar") (feat "min-width" (Just "400px")) [ sampleBlock ] ])
                    |> Expect.equal "@container sidebar (min-width: 400px){p{color:#FF0000;}}"
        , test "boolean (valueless) feature" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (feat "orientation" Nothing) [ sampleBlock ] ])
                    |> Expect.equal "@container (orientation){p{color:#FF0000;}}"
        ]


outputConditionForms : Test
outputConditionForms =
    describe "condition composite emission + parenthesization"
        [ test "and joins with ' and '" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (And [ feat "min-width" (Just "400px"), feat "orientation" (Just "landscape") ]) [ sampleBlock ] ])
                    |> Expect.equal "@container (min-width: 400px) and (orientation: landscape){p{color:#FF0000;}}"
        , test "or with a nested not: the not child is extra-parenthesized, the top-level or is bare" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (Or [ feat "min-width" (Just "400px"), Not (feat "orientation" (Just "landscape")) ]) [ sampleBlock ] ])
                    |> Expect.equal "@container (min-width: 400px) or (not (orientation: landscape)){p{color:#FF0000;}}"
        , test "not of a feature" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (Not (feat "orientation" (Just "landscape"))) [ sampleBlock ] ])
                    |> Expect.equal "@container not (orientation: landscape){p{color:#FF0000;}}"
        , test "raw passthrough" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (Raw "style(--theme: dark)") [ sampleBlock ] ])
                    |> Expect.equal "@container style(--theme: dark){p{color:#FF0000;}}"
        ]


outputRangeForms : Test
outputRangeForms =
    describe "range emission"
        [ test "single lower bound emits feature-first" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (Range { feature = "width", lower = Just ( Gt, "400px" ), upper = Nothing }) [ sampleBlock ] ])
                    |> Expect.equal "@container (width > 400px){p{color:#FF0000;}}"
        , test "eq emits '='" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (Range { feature = "width", lower = Just ( Eq, "400px" ), upper = Nothing }) [ sampleBlock ] ])
                    |> Expect.equal "@container (width = 400px){p{color:#FF0000;}}"
        , test "both bounds emit chained form" <|
            \_ ->
                prettyPrint (sheet [ ContainerRule Nothing (Range { feature = "width", lower = Just ( Le, "200px" ), upper = Just ( Le, "700px" ) }) [ sampleBlock ] ])
                    |> Expect.equal "@container (200px <= width <= 700px){p{color:#FF0000;}}"
        ]


outputConditionQuery : Test
outputConditionQuery =
    describe "ConditionQuery media-query emission"
        [ test "renders the condition string inside @media" <|
            \_ ->
                prettyPrint (sheet [ MediaRule [ ConditionQuery (And [ Feature { feature = "min-width", value = Just "400px" }, Not (Feature { feature = "hover", value = Just "hover" }) ]) ] [ sampleBlock ] ])
                    |> Expect.equal "@media (min-width: 400px) and (not (hover: hover)){p{color:#FF0000;}}"
        ]
