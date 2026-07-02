module Container exposing (outputContainerRule, outputConditionForms, outputRangeForms, outputConditionQuery, resolveWithContainer, resolveNestedContainer)

import Css.Preprocess as Preprocess
import Css.Structure as Structure exposing (..)
import Css.Structure.Output as Output
import Expect
import Test exposing (Test, describe, test)
import TestUtil exposing (outdented, prettyPrint)


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
                Output.prettyPrint (sheet [ ContainerRule Nothing (feat "min-width" (Just "400px")) [ sampleBlock ] ])
                    |> Expect.equal "@container (min-width: 400px){p{color:#FF0000;}}"
        , test "named container" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule (Just "sidebar") (feat "min-width" (Just "400px")) [ sampleBlock ] ])
                    |> Expect.equal "@container sidebar (min-width: 400px){p{color:#FF0000;}}"
        , test "boolean (valueless) feature" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (feat "orientation" Nothing) [ sampleBlock ] ])
                    |> Expect.equal "@container (orientation){p{color:#FF0000;}}"
        ]


outputConditionForms : Test
outputConditionForms =
    describe "condition composite emission + parenthesization"
        [ test "and joins with ' and '" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (And [ feat "min-width" (Just "400px"), feat "orientation" (Just "landscape") ]) [ sampleBlock ] ])
                    |> Expect.equal "@container (min-width: 400px) and (orientation: landscape){p{color:#FF0000;}}"
        , test "or with a nested not: the not child is extra-parenthesized, the top-level or is bare" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (Or [ feat "min-width" (Just "400px"), Not (feat "orientation" (Just "landscape")) ]) [ sampleBlock ] ])
                    |> Expect.equal "@container (min-width: 400px) or (not (orientation: landscape)){p{color:#FF0000;}}"
        , test "not of a feature" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (Not (feat "orientation" (Just "landscape"))) [ sampleBlock ] ])
                    |> Expect.equal "@container not (orientation: landscape){p{color:#FF0000;}}"
        , test "raw passthrough" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (Raw "style(--theme: dark)") [ sampleBlock ] ])
                    |> Expect.equal "@container style(--theme: dark){p{color:#FF0000;}}"
        ]


outputRangeForms : Test
outputRangeForms =
    describe "range emission"
        [ test "single lower bound emits feature-first" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (Range { feature = "width", lower = Just ( Gt, "400px" ), upper = Nothing }) [ sampleBlock ] ])
                    |> Expect.equal "@container (width > 400px){p{color:#FF0000;}}"
        , test "eq emits '='" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (Range { feature = "width", lower = Just ( Eq, "400px" ), upper = Nothing }) [ sampleBlock ] ])
                    |> Expect.equal "@container (width = 400px){p{color:#FF0000;}}"
        , test "both bounds emit chained form" <|
            \_ ->
                Output.prettyPrint (sheet [ ContainerRule Nothing (Range { feature = "width", lower = Just ( Le, "200px" ), upper = Just ( Le, "700px" ) }) [ sampleBlock ] ])
                    |> Expect.equal "@container (200px <= width <= 700px){p{color:#FF0000;}}"
        ]


outputConditionQuery : Test
outputConditionQuery =
    describe "ConditionQuery media-query emission"
        [ test "renders the condition string inside @media" <|
            \_ ->
                Output.prettyPrint (sheet [ MediaRule [ ConditionQuery (And [ Feature { feature = "min-width", value = Just "400px" }, Not (Feature { feature = "hover", value = Just "hover" }) ]) ] [ sampleBlock ] ])
                    |> Expect.equal "@media (min-width: 400px) and (not (hover: hover)){p{color:#FF0000;}}"
        ]


resolveWithContainer : Test
resolveWithContainer =
    let
        cond name value =
            Feature { feature = name, value = value }

        block selectorName props =
            Preprocess.StyleBlock
                (Selector (TypeSelectorSequence (TypeSelector selectorName) []) [] Nothing)
                []
                props

        input =
            Preprocess.stylesheet
                [ Preprocess.Snippet
                    [ Preprocess.StyleBlockDeclaration
                        (block "p"
                            [ Preprocess.AppendProperty (Property "color:#AA0000")
                            , Preprocess.WithContainer Nothing (cond "min-width" (Just "400px")) [ Preprocess.AppendProperty (Property "color:#000000") ]
                            ]
                        )
                    ]
                ]
    in
    describe "withContainer resolves to a ContainerRule declaration"
        [ test "outputs sibling @container after the base block" <|
            \_ ->
                TestUtil.outdented (prettyPrint input)
                    |> Expect.equal (TestUtil.outdented "p{color:#AA0000;}\n@container (min-width: 400px){p{color:#000000;}}")
        ]


resolveNestedContainer : Test
resolveNestedContainer =
    let
        cond name value =
            Feature { feature = name, value = value }

        input =
            Preprocess.stylesheet
                [ Preprocess.Snippet
                    [ Preprocess.StyleBlockDeclaration
                        (Preprocess.StyleBlock
                            (Selector (TypeSelectorSequence (TypeSelector "p") []) [] Nothing)
                            []
                            [ Preprocess.WithContainer Nothing
                                (cond "min-width" (Just "400px"))
                                [ Preprocess.WithContainer Nothing
                                    (cond "orientation" (Just "landscape"))
                                    [ Preprocess.AppendProperty (Property "color:#000000") ]
                                ]
                            ]
                        )
                    ]
                ]
    in
    describe "nested withContainer and-combines into one rule"
        [ test "combines conditions" <|
            \_ ->
                TestUtil.outdented (prettyPrint input)
                    |> Expect.equal (TestUtil.outdented "@container (min-width: 400px) and (orientation: landscape){p{color:#000000;}}")
        ]
