module Container exposing
    ( containerCombinators
    , containerFeatureTest
    , containerFeatures
    , containerHashDistinct
    , containerProperties
    , containerRanges
    , containerRuleConstructors
    , containerSelectorExtension
    , containerUnits
    , globalContainer
    , globalContainerQuery
    , globalNestedContainerCombine
    , outputConditionForms
    , outputConditionQuery
    , outputContainerRule
    , outputRangeForms
    , resolveNestedContainer
    , resolveWithContainer
    , withContainerMediaOuterWins
    , withContainerNamedInnerWins
    , withMediaContainerOuterWins
    )

import Css exposing (cqb, cqh, cqi, cqmax, cqmin, cqw, hex, px)
import Css.Container as Container exposing (..)
import Css.Global exposing (class, footer, p)
import Css.Media as Media exposing (only, screen, withMedia)
import Css.Preprocess as Preprocess exposing (stylesheet)
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


containerFeatureTest : String -> List ( Condition, String ) -> Test
containerFeatureTest label pairs =
    describe (label ++ " container feature")
        (List.indexedMap
            (\n ( cond, expected ) ->
                test (label ++ String.fromInt n) <|
                    \_ ->
                        prettyPrint (stylesheet [ p [ withContainer [ cond ] [ Css.color (hex "000000") ] ] ])
                            |> outdented
                            |> Expect.equal (outdented ("@container " ++ expected ++ "{p{color:#000000;}}"))
            )
            pairs
        )


containerFeatures : Test
containerFeatures =
    describe "Css.Container features"
        [ containerFeatureTest "min-width" [ ( minWidth (px 400), "(min-width: 400px)" ) ]
        , containerFeatureTest "max-width" [ ( maxWidth (px 800), "(max-width: 800px)" ) ]
        , containerFeatureTest "min-height" [ ( minHeight (px 300), "(min-height: 300px)" ) ]
        , containerFeatureTest "max-height" [ ( maxHeight (px 600), "(max-height: 600px)" ) ]
        , containerFeatureTest "min-inline-size" [ ( minInlineSize (px 400), "(min-inline-size: 400px)" ) ]
        , containerFeatureTest "max-inline-size" [ ( maxInlineSize (px 400), "(max-inline-size: 400px)" ) ]
        , containerFeatureTest "min-block-size" [ ( minBlockSize (px 400), "(min-block-size: 400px)" ) ]
        , containerFeatureTest "max-block-size" [ ( maxBlockSize (px 400), "(max-block-size: 400px)" ) ]
        , containerFeatureTest "min-aspect-ratio" [ ( minAspectRatio (ratio 4 3), "(min-aspect-ratio: 4/3)" ) ]
        , containerFeatureTest "max-aspect-ratio" [ ( maxAspectRatio (ratio 16 9), "(max-aspect-ratio: 16/9)" ) ]
        , containerFeatureTest "orientation" [ ( orientation landscape, "(orientation: landscape)" ), ( orientation portrait, "(orientation: portrait)" ) ]
        ]


containerRanges : Test
containerRanges =
    describe "Css.Container range comparisons"
        [ containerFeatureTest "gt" [ ( width |> gt (px 400), "(width > 400px)" ) ]
        , containerFeatureTest "lt" [ ( width |> lt (px 400), "(width < 400px)" ) ]
        , containerFeatureTest "ge" [ ( width |> ge (px 400), "(width >= 400px)" ) ]
        , containerFeatureTest "le" [ ( width |> le (px 400), "(width <= 400px)" ) ]
        , containerFeatureTest "eq" [ ( width |> eq (px 400), "(width = 400px)" ) ]
        , containerFeatureTest "between" [ ( width |> between (px 200) (px 700), "(200px <= width <= 700px)" ) ]
        , containerFeatureTest "aspect-ratio ge" [ ( aspectRatio |> ge (ratio 16 9), "(aspect-ratio >= 16/9)" ) ]
        , containerFeatureTest "inlineSize as feature token" [ ( inlineSize |> gt (px 400), "(inline-size > 400px)" ) ]
        ]


containerCombinators : Test
containerCombinators =
    describe "Css.Container combinators"
        [ containerFeatureTest "anyOf" [ ( anyOf [ minWidth (px 400), orientation landscape ], "(min-width: 400px) or (orientation: landscape)" ) ]
        , containerFeatureTest "allOf inside anyOf" [ ( anyOf [ allOf [ minWidth (px 400), minHeight (px 300) ], orientation landscape ], "((min-width: 400px) and (min-height: 300px)) or (orientation: landscape)" ) ]
        , containerFeatureTest "not under anyOf" [ ( anyOf [ minWidth (px 400), Container.not (orientation landscape) ], "(min-width: 400px) or (not (orientation: landscape))" ) ]
        , containerFeatureTest "rawCondition" [ ( rawCondition "style(--theme: dark)", "style(--theme: dark)" ) ]
        ]


containerRuleConstructors : Test
containerRuleConstructors =
    describe "Css.Container rule constructors"
        [ test "withContainer joins top-level list with and" <|
            \_ ->
                prettyPrint (stylesheet [ p [ withContainer [ minWidth (px 400), orientation landscape ] [ Css.color (hex "000000") ] ] ])
                    |> outdented
                    |> Expect.equal (outdented "@container (min-width: 400px) and (orientation: landscape){p{color:#000000;}}")
        , test "withContainerNamed" <|
            \_ ->
                prettyPrint (stylesheet [ p [ withContainerNamed "sidebar" [ minWidth (px 400) ] [ Css.color (hex "000000") ] ] ])
                    |> outdented
                    |> Expect.equal (outdented "@container sidebar (min-width: 400px){p{color:#000000;}}")
        , test "withContainerQuery raw passthrough" <|
            \_ ->
                prettyPrint (stylesheet [ p [ withContainerQuery "sidebar (min-width: 400px)" [ Css.color (hex "000000") ] ] ])
                    |> outdented
                    |> Expect.equal (outdented "@container sidebar (min-width: 400px){p{color:#000000;}}")
        ]


containerUnits : Test
containerUnits =
    describe "cq* units"
        [ test "cqw renders inside a style" <|
            \_ ->
                prettyPrint (stylesheet [ p [ Css.width (cqw 50) ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{width:50cqw;}")
        , test "cqh" <|
            \_ -> prettyPrint (stylesheet [ p [ Css.width (cqh 50) ] ]) |> outdented |> Expect.equal (outdented "p{width:50cqh;}")
        , test "cqi" <|
            \_ -> prettyPrint (stylesheet [ p [ Css.width (cqi 50) ] ]) |> outdented |> Expect.equal (outdented "p{width:50cqi;}")
        , test "cqb" <|
            \_ -> prettyPrint (stylesheet [ p [ Css.width (cqb 50) ] ]) |> outdented |> Expect.equal (outdented "p{width:50cqb;}")
        , test "cqmin" <|
            \_ -> prettyPrint (stylesheet [ p [ Css.width (cqmin 50) ] ]) |> outdented |> Expect.equal (outdented "p{width:50cqmin;}")
        , test "cqmax" <|
            \_ -> prettyPrint (stylesheet [ p [ Css.width (cqmax 50) ] ]) |> outdented |> Expect.equal (outdented "p{width:50cqmax;}")
        , test "cqw satisfies AbsoluteLength for container features" <|
            \_ ->
                prettyPrint (stylesheet [ p [ withContainer [ minWidth (cqw 50) ] [ Css.color (hex "000000") ] ] ])
                    |> outdented
                    |> Expect.equal (outdented "@container (min-width: 50cqw){p{color:#000000;}}")
        ]


globalContainer : Test
globalContainer =
    let
        input =
            stylesheet
                [ Css.Global.container [ Container.minWidth (px 400) ]
                    [ Css.Global.footer [ Css.maxWidth (px 300) ] ]
                ]

        output =
            "@container (min-width: 400px){footer{max-width:300px;}}"
    in
    describe "Css.Global.container"
        [ test "renders a global @container rule" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented output)
        ]


globalContainerQuery : Test
globalContainerQuery =
    let
        input =
            stylesheet
                [ Css.Global.containerQuery "sidebar (min-width: 400px)"
                    [ Css.Global.footer [ Css.maxWidth (px 300) ] ]
                ]

        output =
            "@container sidebar (min-width: 400px){footer{max-width:300px;}}"
    in
    describe "Css.Global.containerQuery"
        [ test "renders a raw global @container rule" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented output)
        ]


globalNestedContainerCombine : Test
globalNestedContainerCombine =
    let
        input =
            stylesheet
                [ Css.Global.container [ Container.minWidth (px 400) ]
                    [ Css.Global.container [ Container.orientation Container.landscape ]
                        [ Css.Global.footer [ Css.maxWidth (px 300) ] ]
                    ]
                ]
    in
    describe "Css.Global.container nesting and-combines conditions"
        [ test "and-combines conditions, dropping the (empty) outer style block" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented "@container (min-width: 400px) and (orientation: landscape){footer{max-width:300px;}}")
        ]


containerProperties : Test
containerProperties =
    describe "Css.Container establishment properties"
        [ test "containerType size" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerType Container.size ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container-type:size;}")
        , test "containerType normal" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerType Container.normal ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container-type:normal;}")
        , test "containerType inlineSize (dual-role)" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerType inlineSize ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container-type:inline-size;}")
        , test "containerName" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerName "sidebar" ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container-name:sidebar;}")
        , test "containerNames" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerNames [ "a", "b" ] ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container-name:a b;}")
        , test "container shorthand" <|
            \_ ->
                prettyPrint (stylesheet [ p [ container "sidebar" inlineSize ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container:sidebar / inline-size;}")
        ]


containerSelectorExtension : Test
containerSelectorExtension =
    let
        input =
            stylesheet
                [ p
                    [ withContainer [ minWidth (px 400) ]
                        [ Css.Global.children [ Css.Global.a [ Css.color (hex "000000") ] ] ]
                    ]
                ]
    in
    -- Confirm selectors extend correctly inside a container rule (compaction path).
    describe "selector extension inside withContainer"
        [ test "extends selector under @container" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented "@container (min-width: 400px){p > a{color:#000000;}}")
        ]


withMediaContainerOuterWins : Test
withMediaContainerOuterWins =
    let
        input =
            stylesheet
                [ p
                    [ withMedia [ only screen [ Media.minWidth (px 600) ] ]
                        [ withContainer [ minWidth (px 400) ]
                            [ Css.color (hex "000000") ]
                        ]
                    ]
                ]
    in
    -- Documented v1: outer withMedia wins, inner container condition dropped.
    describe "withContainer inside withMedia: outer wins"
        [ test "drops the inner container condition" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented "@media only screen and (min-width: 600px){p{color:#000000;}}")
        ]


withContainerMediaOuterWins : Test
withContainerMediaOuterWins =
    let
        input =
            stylesheet
                [ p
                    [ withContainer [ minWidth (px 400) ]
                        [ withMedia [ only screen [] ]
                            [ Css.color (hex "000000") ]
                        ]
                    ]
                ]
    in
    -- Mirror direction: outer withContainer wins, inner media condition dropped.
    describe "withMedia inside withContainer: outer wins"
        [ test "drops the inner media condition" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented "@container (min-width: 400px){p{color:#000000;}}")
        ]


withContainerNamedInnerWins : Test
withContainerNamedInnerWins =
    let
        input =
            stylesheet
                [ p
                    [ withContainerNamed "outer"
                        [ minWidth (px 400) ]
                        [ withContainerNamed "inner"
                            [ maxWidth (px 700) ]
                            [ Css.color (hex "000000") ]
                        ]
                    ]
                ]
    in
    describe "withContainerNamed nesting: conditions and-combine, inner name wins"
        [ test "inner name wins, conditions and-combine" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented "@container inner (min-width: 400px) and (max-width: 700px){p{color:#000000;}}")
        ]


containerHashDistinct : Test
containerHashDistinct =
    let
        render style =
            prettyPrint (stylesheet [ p [ style ] ])

        a =
            render (withContainer [ minWidth (px 400) ] [ Css.color (hex "000000") ])

        b =
            render (withContainer [ minWidth (px 500) ] [ Css.color (hex "000000") ])
    in
    describe "container condition affects generated CSS (and thus class hash)"
        [ test "different conditions produce different CSS text" <|
            \_ -> Expect.notEqual a b
        ]
