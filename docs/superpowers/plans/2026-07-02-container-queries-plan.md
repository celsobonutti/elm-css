# Container Queries (`@container`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add end-to-end CSS container-query support to elm-css via a new `Css.Container` module modeled on `Css.Media`, plus a shared typed condition grammar reused additively by `Css.Media`, the `cq*` length units, and `Css.Global` snippet constructors.

**Architecture:** Follow the `@media` pipeline exactly — every `@media` touch-point gets a parallel `@container` touch-point. A single generic `QueryCondition leaf` tree lives in the internal `Css.Structure` module and is parameterized by leaf type (`ContainerFeature` for containers, `MediaExpression` for media), so the compiler keeps the two feature vocabularies distinct. Internal modules (`Css.Structure`, `Css.Preprocess`, `Css.Preprocess.Resolve`, `Css.Structure.Output`) are not exposed in `elm.json`, so their changes carry no compatibility constraint; the public surface (`Css.Media`, `Css.Container`, `Css.elm`, `Css.Global`) grows purely additively.

**Tech Stack:** Elm 0.19; `elm-test` (`npm test`) for the suite; `elm-doc-test` for doc examples (config at `tests/elm-doc-test.json`). Class names are murmur3 hashes of the rendered CSS template string.

## Global Constraints

- **Purely additive / minor version bump.** Every existing `Css.Media` function, type, and CSS output must stay byte-identical. Only new functions/types are added. Do not change any existing signature.
- **`Css.Structure`, `Css.Preprocess`, `Css.Preprocess.Resolve`, `Css.Structure.Output` are NOT in `elm.json` exposed-modules** — internal, no compat constraint, but they must keep compiling and keep all existing exports.
- **`between` is inclusive on both ends** — emits `Le` twice: `(a <= f <= b)`.
- **Comparison values use the loose alias** `Value compatible = { compatible | value : String }` so lengths and ratios both fit; no per-feature value checking in v1.
- **Container names are plain `String`** — documented as needing to be valid CSS custom-idents; no validation in v1.
- **Parenthesization rule:** `Feature` and `Range` emit their own parens. Any composite child (`And`/`Or`/`Not`) nested inside another composite is always wrapped in an extra pair of parens. A composite at the TOP level of a rule is NOT wrapped in outer parens (`@container (a) or (b)` — valid per the `<container-condition>` grammar and consistent with how the top-level `and`-join renders).
- **Nesting semantics (v1, documented):** nested `withContainer` inside `withContainer` and-combines into one rule (inner name wins when both named); `withContainer` inside `withMedia` (or vice-versa) keeps the **outer** rule and drops the inner condition (same structural limitation `MediaRule` has today).
- **Names `expr`/`inverse`/`condition` (Media) and `gt`/`lt`/`ge`/`le`/`eq`/`between` are final** unless review says otherwise.
- **Test command:** `npm test` (runs `elm-test`). Run the whole suite unless a task says otherwise. There is no way to run a single Elm test by name from the CLI, so tests are grouped per module and the suite is run after each task.
- **Follow the spec's 9-step implementation order** and its test-first note (write/extend the failing test in `tests/` before the implementation where a test is possible; for internal-type changes that cannot be observed until Output exists, the first observable test appears in the Output task).

---

## File map

- **Modify** `src/Css/Structure.elm` — add `QueryCondition`, `ContainerFeature`, `RangeExpression`, `Comparison`, `ContainerRule` declaration variant, `ConditionQuery` media-query variant, `styleBlockToContainerRule`, and compaction/extension cases. Extend the module `exposing (...)` list.
- **Modify** `src/Css/Structure/Output.elm` — add `conditionToString`, `comparisonToString`, `@container` emission in `prettyPrintDeclaration`, `ConditionQuery` case in `mediaQueryToString`.
- **Modify** `src/Css/Preprocess.elm` — add `WithContainer` `Style` variant and `ContainerRule` `SnippetDeclaration` variant; handle them in `mapProperties`, `mapLastProperty`, `toMediaRule`. Extend `exposing (...)`.
- **Modify** `src/Css/Preprocess/Resolve.elm` — add `resolveContainerRule`, `toContainerRule`, a `WithContainer` case in `applyStyles`, and `ContainerRule`/`WithContainer` cases in `toDeclarations` and the `NestSnippet` `expandDeclaration`.
- **Create** `src/Css/Container.elm` — the public module.
- **Modify** `src/Css/Media.elm` — add opaque `Condition`, `expr`, `anyOf`, `allOf`, `inverse`, `condition`, and `gt`/`lt`/`ge`/`le`/`eq`/`between`. Extend `exposing (...)`.
- **Modify** `src/Css.elm` — add `cqw`/`cqh`/`cqi`/`cqb`/`cqmin`/`cqmax` units. Extend `exposing (...)` and `@docs`.
- **Modify** `src/Css/Global.elm` — add `container`/`containerQuery` snippet constructors. Extend `exposing (...)` and `@docs`.
- **Modify** `elm.json` — add `Css.Container` under `"Styling"`.
- **Create** `tests/Container.elm` — mirrors `tests/Media.elm`.
- **Modify** `tests/Media.elm` — add tests for the new `Css.Media` algebra additions; keep existing tests unchanged (regression).

---

## Task 1: Shared condition tree + declaration variants in `Css.Structure`

**Files:**
- Modify: `src/Css/Structure.elm` (types near lines 59-97; `styleBlockToMediaRule` at 524-531; compaction at 461-466; extension at 191-272 and 310-358; module `exposing` at line 1)

**Interfaces:**
- Produces (all in `Css.Structure`, added to `exposing`):
  - `type QueryCondition leaf = Feature leaf | Range RangeExpression | Not (QueryCondition leaf) | And (List (QueryCondition leaf)) | Or (List (QueryCondition leaf)) | Raw String`
  - `type alias ContainerFeature = { feature : String, value : Maybe String }`
  - `type alias RangeExpression = { feature : String, lower : Maybe ( Comparison, String ), upper : Maybe ( Comparison, String ) }`
  - `type Comparison = Lt | Le | Gt | Ge | Eq`
  - `ContainerRule (Maybe String) (QueryCondition ContainerFeature) (List StyleBlock)` — new `Declaration` variant
  - `ConditionQuery (QueryCondition MediaExpression)` — new `MediaQuery` variant
  - `styleBlockToContainerRule : Maybe String -> QueryCondition ContainerFeature -> Declaration -> Declaration`

Note: this task defines internal types only; nothing is observable in output yet, so its verification is "the project compiles and the existing suite still passes." The first behavioral test lands in Task 2.

- [ ] **Step 1: Add the condition types**

In `src/Css/Structure.elm`, after the `MediaExpression` alias (currently line 86-87) and before `MediaQuery` (line 92), add:

```elm
{-| A generic query-condition tree, parameterized by leaf type so each public
module supplies its own feature vocabulary. Used by both `@media` (via
`ConditionQuery`) and `@container` (via `ContainerRule`).
-}
type QueryCondition leaf
    = Feature leaf
    | Range RangeExpression
    | Not (QueryCondition leaf)
    | And (List (QueryCondition leaf))
    | Or (List (QueryCondition leaf))
    | Raw String


{-| A container feature test. Same shape as `MediaExpression`.
-}
type alias ContainerFeature =
    { feature : String, value : Maybe String }


{-| A range feature test. `lower`/`upper` are the optional bounds:
gt/lt/ge/le/eq set exactly one; between sets both (inclusive, Le/Le).
-}
type alias RangeExpression =
    { feature : String
    , lower : Maybe ( Comparison, String )
    , upper : Maybe ( Comparison, String )
    }


type Comparison
    = Lt
    | Le
    | Gt
    | Ge
    | Eq
```

- [ ] **Step 2: Add the `ContainerRule` declaration variant**

In the `Declaration` type (lines 59-69), add after `MediaRule` (line 61):

```elm
    | ContainerRule (Maybe String) (QueryCondition ContainerFeature) (List StyleBlock)
```

- [ ] **Step 3: Add the `ConditionQuery` media-query variant**

In the `MediaQuery` type (lines 92-96), add after `CustomQuery String` (line 96):

```elm
    | ConditionQuery (QueryCondition MediaExpression)
```

- [ ] **Step 4: Extend the module `exposing` list**

In the `module Css.Structure exposing (...)` header (line 1), add these names (alphabetical placement is not required, but keep them with the other type/function exports): `Comparison(..)`, `ContainerFeature`, `QueryCondition(..)`, `RangeExpression`, and `styleBlockToContainerRule`. The `Declaration(..)` and `MediaQuery(..)` exports already export all constructors, so the new `ContainerRule`/`ConditionQuery` variants are covered.

- [ ] **Step 5: Add `styleBlockToContainerRule`**

After `styleBlockToMediaRule` (line 524-531), add:

```elm
styleBlockToContainerRule : Maybe String -> QueryCondition ContainerFeature -> Declaration -> Declaration
styleBlockToContainerRule name condition declaration =
    case declaration of
        StyleBlockDeclaration styleBlock ->
            ContainerRule name condition [ styleBlock ]

        _ ->
            declaration
```

- [ ] **Step 6: Add the `ContainerRule` compaction case**

In `compactHelp` (lines 452-521), add a case mirroring `MediaRule` (lines 461-466), after the `MediaRule` case:

```elm
        ContainerRule _ _ styleBlocks ->
            if List.all (\(StyleBlock _ _ properties) -> List.isEmpty properties) styleBlocks then
                ( keyframesByName, declarations )

            else
                ( keyframesByName, declaration :: declarations )
```

- [ ] **Step 7: Add `ContainerRule` cases to `extendLastSelector`**

In `extendLastSelector` (lines 191-272), add cases mirroring the three `MediaRule` cases (lines 207-230), placed right after them:

```elm
        (ContainerRule name condition ((StyleBlock only [] properties) :: [])) :: [] ->
            let
                newStyleBlock =
                    StyleBlock (appendRepeatableSelector selector only) [] properties
            in
            [ ContainerRule name condition [ newStyleBlock ] ]

        (ContainerRule name condition ((StyleBlock first rest properties) :: [])) :: [] ->
            let
                newRest =
                    mapLast (appendRepeatableSelector selector) rest

                newStyleBlock =
                    StyleBlock first newRest properties
            in
            [ ContainerRule name condition [ newStyleBlock ] ]

        (ContainerRule name condition (first :: rest)) :: [] ->
            case extendLastSelector selector [ ContainerRule name condition rest ] of
                (ContainerRule newName newCondition newStyleBlocks) :: [] ->
                    [ ContainerRule newName newCondition (first :: newStyleBlocks) ]

                newDeclarations ->
                    newDeclarations
```

- [ ] **Step 8: Add the `ContainerRule` case to `concatMapLastStyleBlock`**

In `concatMapLastStyleBlock` (lines 310-358), add cases mirroring the two `MediaRule` cases (lines 320-329), right after them:

```elm
        (ContainerRule name condition (styleBlock :: [])) :: [] ->
            [ ContainerRule name condition (update styleBlock) ]

        (ContainerRule name condition (first :: rest)) :: [] ->
            case concatMapLastStyleBlock update [ ContainerRule name condition rest ] of
                (ContainerRule newName newCondition newStyleBlocks) :: [] ->
                    [ ContainerRule newName newCondition (first :: newStyleBlocks) ]

                newDeclarations ->
                    newDeclarations
```

- [ ] **Step 9: Add the `ContainerRule` case to `appendProperty`**

In `appendProperty` (lines 156-183), add after the `MediaRule` case (lines 165-168):

```elm
        (ContainerRule name condition styleBlocks) :: [] ->
            [ ContainerRule name
                condition
                (mapLast (withPropertyAppended property) styleBlocks)
            ]
```

- [ ] **Step 10: Compile and run the suite**

Run: `npx elm make src/Css/Structure.elm --output=/dev/null`
Expected: compiles with no errors (a `MediaQuery` exhaustiveness warning may appear from other modules — that is handled in Task 2; `Css.Structure` itself must compile).

Run: `npm test`
Expected: Task 2 has not touched Output yet, so `mediaQueryToString`/`prettyPrintDeclaration` will now fail to compile on the new variants. If the suite fails to compile because of the new `MediaQuery`/`Declaration` variants in `Css.Structure.Output`, that is expected — proceed to Task 2, which adds those cases. Otherwise the suite must pass unchanged.

- [ ] **Step 11: Commit**

```bash
git add src/Css/Structure.elm
git commit -m "feat(structure): add QueryCondition tree, ContainerRule, and ConditionQuery variants

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 2: Serialization in `Css.Structure.Output`

**Files:**
- Modify: `src/Css/Structure/Output.elm` (`prettyPrintDeclaration` at 57-95; `mediaQueryToString` at 98-122; add `conditionToString`/`comparisonToString` near `mediaExpressionToString` at 137-145)
- Test: `tests/Container.elm` (create — first behavioral tests) and this task also unblocks the suite compilation from Task 1.

**Interfaces:**
- Consumes: `QueryCondition`, `ContainerFeature`, `RangeExpression`, `Comparison(..)`, `ContainerRule`, `ConditionQuery` from Task 1.
- Produces (in `Css.Structure.Output`, add to `exposing`): `conditionToString : (leaf -> String) -> QueryCondition leaf -> String`. Existing `mediaQueryToString` gains a `ConditionQuery` case; `prettyPrintDeclaration` gains a `ContainerRule` case.

- [ ] **Step 1: Write a failing test (bootstrap `tests/Container.elm`)**

Create `tests/Container.elm` with a minimal harness that exercises `@container` output through the public API that will exist after Task 5. Because Task 5 does not exist yet, this first test drives Output directly through `Css.Structure` + `Css.Preprocess`-free construction is awkward; instead, write the first Output test against a hand-built `Structure.Stylesheet` compiled with `Css.Structure.Output.prettyPrint`. Create:

```elm
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
```

Formatting caveat: the exact expected strings above assume `prettyPrint`'s block formatting matches `tests/Media.elm` conventions — if the first run shows whitespace/newline differences, pipe through `TestUtil.outdented` on both sides (as `tests/Media.elm` does) and match the observed layout; the load-bearing assertions are the `@container` prelude and condition text.

Register these four tests in `tests/Tests.elm` is **not** required — `elm-test` auto-discovers every top-level `Test` value in every module under `tests/`. Confirm this by noting `tests/Media.elm` tests run without being imported into `Tests.elm`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npm test`
Expected: compile failure — `Css.Structure.Output` does not yet handle `ContainerRule`/`ConditionQuery`, and `conditionToString` does not exist.

- [ ] **Step 3: Add `comparisonToString` and `conditionToString`**

In `src/Css/Structure/Output.elm`, after `mediaExpressionToString` (ends line 145), add:

```elm
comparisonToString : Comparison -> String
comparisonToString comparison =
    case comparison of
        Lt ->
            "<"

        Le ->
            "<="

        Gt ->
            ">"

        Ge ->
            ">="

        Eq ->
            "="


containerFeatureToString : ContainerFeature -> String
containerFeatureToString =
    mediaExpressionToString


rangeToString : RangeExpression -> String
rangeToString { feature, lower, upper } =
    case ( lower, upper ) of
        ( Just ( lowerCmp, lowerVal ), Just ( upperCmp, upperVal ) ) ->
            "("
                ++ lowerVal
                ++ " "
                ++ comparisonToString lowerCmp
                ++ " "
                ++ feature
                ++ " "
                ++ comparisonToString upperCmp
                ++ " "
                ++ upperVal
                ++ ")"

        ( Just ( cmp, val ), Nothing ) ->
            "(" ++ feature ++ " " ++ comparisonToString cmp ++ " " ++ val ++ ")"

        ( Nothing, Just ( cmp, val ) ) ->
            "(" ++ feature ++ " " ++ comparisonToString cmp ++ " " ++ val ++ ")"

        ( Nothing, Nothing ) ->
            "(" ++ feature ++ ")"


{-| Serialize a query condition. `leafToString` renders the leaf feature
(already including its own parentheses). Composite children nested inside a
composite are wrapped in an extra pair of parens to keep the CSS valid.
-}
conditionToString : (leaf -> String) -> QueryCondition leaf -> String
conditionToString leafToString condition =
    let
        grouped child =
            case child of
                Feature _ ->
                    conditionToString leafToString child

                Range _ ->
                    conditionToString leafToString child

                Raw _ ->
                    conditionToString leafToString child

                _ ->
                    "(" ++ conditionToString leafToString child ++ ")"
    in
    case condition of
        Feature leaf ->
            leafToString leaf

        Range range ->
            rangeToString range

        Not child ->
            "not " ++ grouped child

        And children ->
            String.join " and " (List.map grouped children)

        Or children ->
            String.join " or " (List.map grouped children)

        Raw str ->
            str
```

Note on the `between`/chained form: the spec's example `(200px <= width <= 700px)` uses `Le` for both bounds; `rangeToString` renders the lower bound value-first and the upper bound feature-`cmp`-value, matching the example. This is why `between` (Task 5) sets `lower = Just ( Le, low )` and `upper = Just ( Le, high )`.

- [ ] **Step 4: Add the `ContainerRule` case to `prettyPrintDeclaration`**

In `prettyPrintDeclaration` (lines 57-95), add after the `MediaRule` case (lines 63-71):

```elm
        ContainerRule name condition styleBlocks ->
            let
                blocks =
                    Css.String.mapJoin prettyPrintStyleBlock "\n" styleBlocks

                namePrefix =
                    case name of
                        Just str ->
                            str ++ " "

                        Nothing ->
                            ""
            in
            "@container "
                ++ namePrefix
                ++ conditionToString containerFeatureToString condition
                ++ "{"
                ++ blocks
                ++ "}"
```

- [ ] **Step 5: Add the `ConditionQuery` case to `mediaQueryToString`**

In `mediaQueryToString` (lines 98-122), add before `CustomQuery str` in the `case`:

```elm
        ConditionQuery condition ->
            conditionToString mediaExpressionToString condition
```

- [ ] **Step 6: Export `conditionToString`**

In the `module Css.Structure.Output exposing (...)` header (line 1), add `conditionToString`.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `npm test`
Expected: the four new `Container` suites pass; the entire existing suite (including all of `tests/Media.elm`) passes unchanged.

- [ ] **Step 8: Commit**

```bash
git add src/Css/Structure/Output.elm tests/Container.elm
git commit -m "feat(output): serialize @container rules and query conditions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 3: `WithContainer` in `Css.Preprocess`

**Files:**
- Modify: `src/Css/Preprocess.elm` (`Style` type at 27-35; `SnippetDeclaration` at 41-50; `toMediaRule` at 57-89; `mapProperties` at 92-114; `mapLastProperty` at 130-152; module `exposing` at line 1)

**Interfaces:**
- Consumes: `Structure.QueryCondition`, `Structure.ContainerFeature` from Task 1.
- Produces (in `Css.Preprocess`, add to `exposing`):
  - `Style` variant `WithContainer (Maybe String) (Structure.QueryCondition Structure.ContainerFeature) (List Style)`
  - `SnippetDeclaration` variant `ContainerRule (Maybe String) (Structure.QueryCondition Structure.ContainerFeature) (List StyleBlock)`

This task changes internal types only; observable behavior arrives in Task 4/5. Verify by compiling and running the suite (which must remain green because the new variants are handled everywhere they are matched).

- [ ] **Step 1: Add the `WithContainer` `Style` variant**

In `src/Css/Preprocess.elm`, in the `Style` type (lines 27-35), add after `WithMedia` (line 32):

```elm
    | WithContainer (Maybe String) (Structure.QueryCondition Structure.ContainerFeature) (List Style)
```

- [ ] **Step 2: Add the `ContainerRule` `SnippetDeclaration` variant**

In the `SnippetDeclaration` type (lines 41-50), add after `MediaRule` (line 43):

```elm
    | ContainerRule (Maybe String) (Structure.QueryCondition Structure.ContainerFeature) (List StyleBlock)
```

- [ ] **Step 3: Handle `WithContainer` in `mapProperties`**

In `mapProperties` (lines 92-114), add a case alongside `WithMedia` (lines 107-108):

```elm
        WithContainer _ _ _ ->
            style
```

- [ ] **Step 4: Handle `WithContainer` in `mapLastProperty`**

In `mapLastProperty` (lines 130-152), add a case alongside `WithMedia` (lines 145-146):

```elm
        WithContainer _ _ _ ->
            style
```

- [ ] **Step 5: Extend the module `exposing` list**

In the `module Css.Preprocess exposing (...)` header (line 1), the `Style(..)` and `SnippetDeclaration(..)` exports already export all constructors, so the new variants are covered. No change needed unless the header lists constructors individually — confirm it uses `Style(..)` and `SnippetDeclaration(..)` (it does). No edit required in this step; leave as a checked verification.

- [ ] **Step 6: Compile and run the suite**

Run: `npx elm make src/Css/Preprocess.elm --output=/dev/null`
Expected: compiles (a non-exhaustive-`case` warning may surface in `Resolve.elm` when the whole project is built — handled in Task 4).

Run: `npm test`
Expected: if the suite fails to compile because `Resolve.elm` does not yet handle the new variants in its `case` expressions, that is expected — proceed to Task 4. Otherwise, green.

- [ ] **Step 7: Commit**

```bash
git add src/Css/Preprocess.elm
git commit -m "feat(preprocess): add WithContainer style + ContainerRule snippet declaration

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 4: Resolution + nesting semantics in `Css.Preprocess.Resolve`

**Files:**
- Modify: `src/Css/Preprocess/Resolve.elm` (`toMediaRule` at 43-76; `toDeclarations` at 95-124; `applyStyles` at 137-259; the `NestSnippet` `expandDeclaration` at 163-206)
- Test: `tests/Container.elm` (add nesting behavior tests). These are the first tests that exercise the resolve pipeline, but they still need the public `Css.Container` constructors from Task 5. To keep this task independently testable, drive resolution here through `Css.Preprocess` values constructed directly (the `WithContainer` constructor is public within the internal module).

**Interfaces:**
- Consumes: `Preprocess.WithContainer`, `Preprocess.ContainerRule`, `Structure.styleBlockToContainerRule`, `Structure.ContainerRule`.
- Produces: `resolveContainerRule : Maybe String -> Structure.QueryCondition Structure.ContainerFeature -> List Preprocess.StyleBlock -> List Structure.Declaration`; `toContainerRule : Maybe String -> Structure.QueryCondition Structure.ContainerFeature -> Structure.Declaration -> Structure.Declaration`.

- [ ] **Step 1: Write failing resolve/nesting tests**

Add to `tests/Container.elm` (append these `Test` values and add them to the module `exposing` list):

```elm
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
```

This uses `import Css.Preprocess as Preprocess` and `import TestUtil exposing (outdented, prettyPrint)`. Add those imports to `tests/Container.elm`.

Also add a nested-and-combine test:

```elm
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: compile failure in `Resolve.elm` (non-exhaustive cases for `WithContainer`/`ContainerRule`), plus the new tests unresolved.

- [ ] **Step 3: Add `toContainerRule`**

In `src/Css/Preprocess/Resolve.elm`, after `toMediaRule` (lines 43-76), add. The `Structure.ContainerRule` branch is what makes nested `withContainer` and-combine and lets the inner name win:

```elm
toContainerRule : Maybe String -> Structure.QueryCondition Structure.ContainerFeature -> Structure.Declaration -> Structure.Declaration
toContainerRule name condition declaration =
    case declaration of
        Structure.StyleBlockDeclaration structureStyleBlock ->
            Structure.ContainerRule name condition [ structureStyleBlock ]

        Structure.ContainerRule innerName innerCondition structureStyleBlocks ->
            let
                combinedName =
                    case innerName of
                        Just _ ->
                            innerName

                        Nothing ->
                            name

                combinedCondition =
                    Structure.And [ condition, innerCondition ]
            in
            Structure.ContainerRule combinedName combinedCondition structureStyleBlocks

        Structure.MediaRule _ _ ->
            -- outer wins: withMedia inside withContainer keeps the media rule,
            -- the container condition is dropped (documented v1 limitation).
            declaration

        Structure.SupportsRule str declarations ->
            Structure.SupportsRule str (List.map (toContainerRule name condition) declarations)

        Structure.DocumentRule str1 str2 str3 str4 structureStyleBlock ->
            Structure.DocumentRule str1 str2 str3 str4 structureStyleBlock

        Structure.PageRule _ ->
            declaration

        Structure.FontFace _ ->
            declaration

        Structure.Keyframes _ ->
            declaration

        Structure.Viewport _ ->
            declaration

        Structure.CounterStyle _ ->
            declaration

        Structure.FontFeatureValues _ ->
            declaration
```

Note the `And [ condition, innerCondition ]` nesting produces `(min-width: 400px) and (orientation: landscape)` — both are `Feature`s, so neither gets extra-parenthesized per the Task 2 rule. This matches the `resolveNestedContainer` expectation.

- [ ] **Step 4: Add the `MediaRule`→outer-wins case for the reverse direction**

The reverse (`withContainer` inside `withMedia`) is already handled by the existing `toMediaRule`: extend its `Structure.ContainerRule` handling so the outer media rule wins and the container condition is dropped. In `toMediaRule` (lines 43-76), add a case after `Structure.MediaRule` (lines 49-50):

```elm
        Structure.ContainerRule _ _ structureStyleBlocks ->
            -- outer wins: withContainer inside withMedia collapses to a MediaRule,
            -- dropping the container condition (documented v1 limitation).
            Structure.MediaRule mediaQueries structureStyleBlocks
```

- [ ] **Step 5: Add `resolveContainerRule`**

After `resolveMediaRule` (lines 24-31), add:

```elm
resolveContainerRule : Maybe String -> Structure.QueryCondition Structure.ContainerFeature -> List Preprocess.StyleBlock -> List Structure.Declaration
resolveContainerRule name condition styleBlocks =
    let
        handleStyleBlock : Preprocess.StyleBlock -> List Structure.Declaration
        handleStyleBlock styleBlock =
            List.map (toContainerRule name condition) (expandStyleBlock styleBlock)
    in
    List.concatMap handleStyleBlock styleBlocks
```

- [ ] **Step 6: Handle `Preprocess.ContainerRule` in `toDeclarations`**

In `toDeclarations` (lines 95-124), add after the `Preprocess.MediaRule` case (lines 101-102):

```elm
        Preprocess.ContainerRule name condition styleBlocks ->
            resolveContainerRule name condition styleBlocks
```

- [ ] **Step 7: Handle `Preprocess.ContainerRule` in the `NestSnippet` `expandDeclaration`**

In `applyStyles`' `NestSnippet` branch, the inner `expandDeclaration` (lines 163-206) has a `Preprocess.MediaRule` case (lines 183-184). Add after it:

```elm
                        Preprocess.ContainerRule name condition styleBlocks ->
                            resolveContainerRule name condition styleBlocks
```

- [ ] **Step 8: Add the `WithContainer` case to `applyStyles`**

In `applyStyles` (lines 137-259), add a branch mirroring `WithMedia` (lines 238-255), placed right after it. This produces a sibling `@container` declaration off the collected selectors:

```elm
        (Preprocess.WithContainer name condition nestedStyles) :: rest ->
            let
                extraDeclarations =
                    case collectSelectors declarations of
                        [] ->
                            []

                        firstSelector :: otherSelectors ->
                            Structure.StyleBlock firstSelector otherSelectors []
                                |> Structure.StyleBlockDeclaration
                                |> List.singleton
                                |> applyStyles nestedStyles
                                |> List.map (styleBlockToContainerRule name condition)
            in
            applyStyles rest declarations ++ extraDeclarations
```

Add `styleBlockToContainerRule` to the import from `Css.Structure` (line 9 currently imports `styleBlockToMediaRule`):

```elm
import Css.Structure as Structure exposing (Property, mapLast, styleBlockToContainerRule, styleBlockToMediaRule)
```

Note: when `nestedStyles` itself contains a `WithContainer`, `applyStyles nestedStyles` produces a nested `Structure.ContainerRule`, and `styleBlockToContainerRule name condition` then wraps it — but `styleBlockToContainerRule` only rewrites `StyleBlockDeclaration`, leaving an inner `ContainerRule` untouched, which would NOT and-combine. To make nested `withContainer` and-combine per the spec, change the final `List.map` to use `toContainerRule` instead, which handles the `Structure.ContainerRule` case:

```elm
                                |> List.map (toContainerRule name condition)
```

Use `toContainerRule` (not `styleBlockToContainerRule`) in this branch. `styleBlockToContainerRule` still exists in `Css.Structure` for symmetry with `styleBlockToMediaRule` and may be dropped from the import if unused — keep the import only if referenced elsewhere. Verify with the compiler.

- [ ] **Step 9: Run tests to verify they pass**

Run: `npm test`
Expected: `resolveWithContainer` and `resolveNestedContainer` pass; entire existing suite green.

- [ ] **Step 10: Commit**

```bash
git add src/Css/Preprocess/Resolve.elm tests/Container.elm
git commit -m "feat(resolve): resolve @container rules with documented nesting semantics

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 5: Public `Css.Container` module

**Files:**
- Create: `src/Css/Container.elm`
- Test: `tests/Container.elm` (add public-API tests mirroring `tests/Media.elm` conventions)

**Interfaces:**
- Consumes: `Css.Preprocess.WithContainer`, `Structure.QueryCondition`, `Structure.ContainerFeature`, `Structure.Range`, `Structure.RangeExpression`, `Structure.Comparison(..)`, `Structure.Feature`, `Structure.And`, `Structure.Or`, `Structure.Not`, `Structure.Raw`. `Css.AbsoluteLength`-style constraint reused from `Css.Media` (`AbsoluteLength compatible = { compatible | value : String, absoluteLength : Compatible }`).
- Produces the full public surface below. Later tasks (Task 6 `Css.Media`) reuse the feature tokens `width`, `height`, `aspectRatio`, `inlineSize`, `blockSize` and the `ratio` constructor from this module.

- [ ] **Step 1: Write failing public-API tests**

Add to `tests/Container.elm` a harness mirroring `tests/Media.elm`'s `expectFeatureWorks`/`testFeature`, but for `@container`. Add these `Test` values (and to module `exposing`), importing `import Css exposing (..)`, `import Css.Container as Container exposing (..)`, `import Css.Global exposing (p, class)`, `import Css.Preprocess exposing (stylesheet)`:

```elm
basicContainer : List Condition -> Snippet
basicContainer conditions =
    -- withContainer produces a Style; attach to a global p snippet
    p [ backgroundColor (hex "FF0000") |> always (withContainer conditions [ Css.color (hex "000000") ]) ]
```

Because `withContainer` returns a `Style` and global snippets take `List Style`, write the harness as:

```elm
containerFeatureTest : String -> List ( Condition, String ) -> Test
containerFeatureTest label pairs =
    describe (label ++ " container feature")
        (List.indexedMap
            (\n ( cond, expected ) ->
                let
                    actual =
                        prettyPrint (stylesheet [ p [ withContainer [ cond ] [ Css.color (hex "000000") ] ] ])

                    expectedStr =
                        "@container " ++ expected ++ "{p{color:#000000;}}"
                in
                test (label ++ String.fromInt n) <| \_ -> Expect.equal expectedStr (outdented (prettyPrint (stylesheet [ p [ withContainer [ cond ] [ Css.color (hex "000000") ] ] ])))
            )
            pairs
        )
```

Simplify to a single clean form (avoid the duplicate `actual`); the essential assertions to include:

```elm
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
```

Note: the top-level `withContainer` list is joined with `and`, so `withContainer [ minWidth (px 400), orientation landscape ]` emits `(min-width: 400px) and (orientation: landscape)` (no outer parens because they are both `Feature`s at the top level). Add a test for that two-element top-level form, and for `withContainerNamed`, `withContainerQuery`, and the establishment properties + units (units are also covered in Task 7; include a smoke test here for `containerType`, `container`, `containerName`, `containerNames`):

```elm
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


containerProperties : Test
containerProperties =
    describe "Css.Container establishment properties"
        [ test "containerType size" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerType size ] ])
                    |> outdented
                    |> Expect.equal (outdented "p{container-type:size;}")
        , test "containerType normal" <|
            \_ ->
                prettyPrint (stylesheet [ p [ containerType normal ] ])
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
```

The `containerFeatureTest` helper should be defined cleanly (single `actual`):

```elm
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: compile failure — `Css.Container` does not exist.

- [ ] **Step 3: Create `src/Css/Container.elm` — module header + `Condition`**

```elm
module Css.Container exposing
    ( Condition
    , withContainer, withContainerNamed, withContainerQuery
    , anyOf, allOf, not, rawCondition
    , minWidth, maxWidth, minHeight, maxHeight
    , minInlineSize, maxInlineSize, minBlockSize, maxBlockSize
    , minAspectRatio, maxAspectRatio
    , width, height, inlineSize, blockSize, aspectRatio
    , gt, lt, ge, le, eq, between
    , orientation, Landscape, Portrait, landscape, portrait
    , ContainerTypeValue, containerType, normal, size
    , containerName, containerNames, container
    , Ratio, ratio
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
```

- [ ] **Step 4: Add the rule constructors**

`withContainer` joins the top-level list with `And`; a single-element list is emitted bare. Follow this exactly so a single feature does not get a spurious `And` wrapper (the Output `And` of one child would join zero separators and still render one condition, but to match `tests/Media.elm`'s `all`-style behavior and keep output minimal, collapse a singleton):

```elm
withContainer : List Condition -> List Style -> Style
withContainer conditions =
    Preprocess.WithContainer Nothing (combineAnd conditions)


withContainerNamed : String -> List Condition -> List Style -> Style
withContainerNamed name conditions =
    Preprocess.WithContainer (Just name) (combineAnd conditions)


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
```

Note: `withContainerQuery "sidebar (min-width: 400px)"` emits `@container ` ++ `sidebar (min-width: 400px)` because the `Raw` string is the whole condition and `name` is `Nothing` — matching the test. This is the raw whole-condition escape hatch (name is baked into the string).

- [ ] **Step 5: Add the combinators**

```elm
anyOf : List Condition -> Condition
anyOf conditions =
    Condition (Structure.Or (List.map unwrap conditions))


allOf : List Condition -> Condition
allOf conditions =
    Condition (Structure.And (List.map unwrap conditions))


not : Condition -> Condition
not condition =
    Condition (Structure.Not (unwrap condition))


rawCondition : String -> Condition
rawCondition raw =
    Condition (Structure.Raw raw)
```

- [ ] **Step 6: Add the min/max features**

```elm
feature : String -> Value compatible -> Condition
feature key { value } =
    Condition (Structure.Feature { feature = key, value = Just value })


minWidth : AbsoluteLength compatible -> Condition
minWidth value =
    feature "min-width" value


maxWidth : AbsoluteLength compatible -> Condition
maxWidth value =
    feature "max-width" value


minHeight : AbsoluteLength compatible -> Condition
minHeight value =
    feature "min-height" value


maxHeight : AbsoluteLength compatible -> Condition
maxHeight value =
    feature "max-height" value


minInlineSize : AbsoluteLength compatible -> Condition
minInlineSize value =
    feature "min-inline-size" value


maxInlineSize : AbsoluteLength compatible -> Condition
maxInlineSize value =
    feature "max-inline-size" value


minBlockSize : AbsoluteLength compatible -> Condition
minBlockSize value =
    feature "min-block-size" value


maxBlockSize : AbsoluteLength compatible -> Condition
maxBlockSize value =
    feature "max-block-size" value


minAspectRatio : Ratio -> Condition
minAspectRatio value =
    feature "min-aspect-ratio" value


maxAspectRatio : Ratio -> Condition
maxAspectRatio value =
    feature "max-aspect-ratio" value
```

- [ ] **Step 7: Add the `Ratio` type + constructor**

Defined locally (structurally identical to `Css.Media.Ratio`), so `Css.Container` needs no `Css.Media` import:

```elm
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
```

- [ ] **Step 8: Add orientation values + feature**

```elm
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
```

- [ ] **Step 9: Add the feature tokens for range syntax**

These are keyword records, NOT lengths. Their `.value` field holds the CSS feature name string (used to build the `RangeExpression.feature`). `width`/`height`/`aspectRatio` carry `mediaFeature` so `Css.Media`'s comparisons accept them; `inlineSize`/`blockSize` do not. `inlineSize` additionally carries `containerTypeValue` (dual-role — see Step 11).

```elm
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
```

- [ ] **Step 10: Add the comparison builders**

Value-first so pipelines read feature-first. The `FeatureToken f` constraint requires `containerFeature`; the token's `.value` is the feature name, the comparison value's `.value` is the length/ratio string:

```elm
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


gt : Value compatible -> FeatureToken f -> Condition
gt =
    rangeCondition Structure.Gt


lt : Value compatible -> FeatureToken f -> Condition
lt =
    rangeCondition Structure.Lt


ge : Value compatible -> FeatureToken f -> Condition
ge =
    rangeCondition Structure.Ge


le : Value compatible -> FeatureToken f -> Condition
le =
    rangeCondition Structure.Le


eq : Value compatible -> FeatureToken f -> Condition
eq =
    rangeCondition Structure.Eq


between : Value compatibleLow -> Value compatibleHigh -> FeatureToken f -> Condition
between low high token =
    Condition
        (Structure.Range
            { feature = token.value
            , lower = Just ( Structure.Le, low.value )
            , upper = Just ( Structure.Le, high.value )
            }
        )
```

- [ ] **Step 11: Add the establishment properties**

`ContainerTypeValue a` is an extensible keyword record. `normal`/`size` carry only `containerTypeValue`; `inlineSize` (Step 9) carries `containerTypeValue` too, so `containerType inlineSize` compiles. The `container` shorthand emits `container: <name> / <type-value>`.

```elm
{-| A value for the `container-type` property. -}
type alias ContainerTypeValue a =
    { a | value : String, containerTypeValue : Compatible }


{-| `container-type: normal` -}
normal : { value : String, containerTypeValue : Compatible }
normal =
    { value = "normal", containerTypeValue = Compatible }


{-| `container-type: size` -}
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


{-| The [`container-name`](https://developer.mozilla.org/en-US/docs/Web/CSS/container-name) property. -}
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
```

Confirm `Css.property : String -> String -> Style` exists and is exposed (it is used throughout `Css.elm`). If the exposed name differs, use the exposed custom-property helper; check `grep -n "^property " src/Css.elm`.

- [ ] **Step 12: Run tests to verify they pass**

Run: `npm test`
Expected: all `Css.Container` public-API suites pass; entire suite green.

- [ ] **Step 13: Commit**

```bash
git add src/Css/Container.elm tests/Container.elm
git commit -m "feat(container): add public Css.Container module

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 6: `Css.Media` additive condition algebra

**Files:**
- Modify: `src/Css/Media.elm` (module `exposing` at 1-19; add new types/functions near the rule constructors ~line 132; reuse the private `feature` helper and `Value` alias at 127-129, 949-951)
- Test: `tests/Media.elm` (add new `Test` values; do not modify existing ones)

**Interfaces:**
- Consumes: `Structure.QueryCondition`, `Structure.MediaExpression`, `Structure.Feature`, `Structure.And`, `Structure.Or`, `Structure.Not`, `Structure.Range`, `Structure.Comparison(..)`, `Structure.ConditionQuery`; the `Css.Container` feature tokens (via record structural typing — no import needed since only `.value`/`.mediaFeature` fields are read).
- Produces (add to `Css.Media` `exposing`): `Condition` (opaque), `expr`, `anyOf`, `allOf`, `inverse`, `condition`, `gt`, `lt`, `ge`, `le`, `eq`, `between`.

- [ ] **Step 1: Write failing tests in `tests/Media.elm`**

Append new `Test` values (and add them to `tests/Media.elm`'s module `exposing` list). These import `Css.Container` for the shared tokens: add `import Css.Container as Container` to `tests/Media.elm`.

```elm
mediaConditionAlgebra : Test
mediaConditionAlgebra =
    let
        input =
            stylesheet
                [ body
                    [ withMedia
                        [ condition
                            [ expr (Media.minWidth (px 400))
                            , anyOf [ expr (orientation landscape), inverse (expr (Media.hover canHover)) ]
                            ]
                        ]
                        [ Css.color (hex "000000") ]
                    ]
                ]

        output =
            "body{}\n@media (min-width: 400px) and ((orientation: landscape) or (not (hover: hover))){body{color:#000000;}}"
    in
    describe "Css.Media condition algebra"
        [ test "renders nested and/or/not" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented output)
        ]


mediaRangeComparisons : Test
mediaRangeComparisons =
    let
        input =
            stylesheet
                [ body
                    [ withMedia [ condition [ Container.width |> gt (px 600) ] ]
                        [ Css.color (hex "000000") ]
                    ]
                ]

        output =
            "body{}\n@media (width > 600px){body{color:#000000;}}"
    in
    describe "Css.Media range comparisons with shared Container tokens"
        [ test "renders width > 600px" <|
            \_ ->
                outdented (prettyPrint input)
                    |> Expect.equal (outdented output)
        ]
```

Note: `body{}` may or may not appear depending on whether an empty base block is emitted; `compactHelp` drops style blocks with no properties, so the base `body` with only a `withMedia` produces no base rule. Adjust the expected string after observing the failing-then-passing run — if `compactHelp` drops the empty base, the expected output is just the `@media ...` line. Set the expectation to match the actual pipeline (the base `body` here has no direct properties, so expect only the `@media` line). Write the expectation without `body{}`:

```elm
        output =
            "@media (min-width: 400px) and ((orientation: landscape) or (not (hover: hover))){body{color:#000000;}}"
```

and likewise for the range test:

```elm
        output =
            "@media (width > 600px){body{color:#000000;}}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: compile failure — `condition`, `expr`, `anyOf`, `allOf`, `inverse`, `gt`, `Condition` do not exist in `Css.Media`.

- [ ] **Step 3: Extend the `Css.Media` `exposing` list**

In the header (lines 1-19), add to the appropriate `@docs` group and the exposing list: `Condition`, `expr`, `anyOf`, `allOf`, `inverse`, `condition`, `gt`, `lt`, `ge`, `le`, `eq`, `between`. Add a matching `@docs` line, e.g. under a new `# Condition algebra` heading in the module doc comment.

- [ ] **Step 4: Add the `Condition` type and algebra**

After the rule constructors (`withMediaQuery` ends ~line 180), add:

```elm
{-| An opaque media condition, for building `and`/`or`/`not` media queries with
the range syntax. Distinct from `Css.Container.Condition` so the compiler keeps
media features out of `@container` queries and vice versa.
-}
type Condition
    = Condition (Structure.QueryCondition Structure.MediaExpression)


unwrapCondition : Condition -> Structure.QueryCondition Structure.MediaExpression
unwrapCondition (Condition c) =
    c


{-| Lift an existing media `Expression` into the condition algebra.

    expr (minWidth (px 400))

-}
expr : Expression -> Condition
expr expression =
    Condition (Structure.Feature expression)


{-| Combine conditions with `or`.
-}
anyOf : List Condition -> Condition
anyOf conditions =
    Condition (Structure.Or (List.map unwrapCondition conditions))


{-| Combine conditions with `and`.
-}
allOf : List Condition -> Condition
allOf conditions =
    Condition (Structure.And (List.map unwrapCondition conditions))


{-| Negate a condition. Named `inverse` because `not` is taken by media-type negation.
-}
inverse : Condition -> Condition
inverse c =
    Condition (Structure.Not (unwrapCondition c))


{-| Turn a list of conditions (joined with `and`) into a `MediaQuery` that slots
into `withMedia`'s query list.
-}
condition : List Condition -> MediaQuery
condition conditions =
    Structure.ConditionQuery (combineAnd conditions)


combineAnd : List Condition -> Structure.QueryCondition Structure.MediaExpression
combineAnd conditions =
    case List.map unwrapCondition conditions of
        only :: [] ->
            only

        many ->
            Structure.And many
```

- [ ] **Step 5: Add the range comparisons**

The `MediaFeatureToken f` requires `mediaFeature`, so `Container.width`/`height`/`aspectRatio` are accepted but `Container.inlineSize`/`blockSize` are rejected. Value-first, mirroring `Css.Container`:

```elm
type alias MediaFeatureToken f =
    { f | value : String, mediaFeature : Compatible }


mediaRange : Structure.Comparison -> Value compatible -> MediaFeatureToken f -> Condition
mediaRange comparison val token =
    Condition
        (Structure.Range
            { feature = token.value
            , lower = Just ( comparison, val.value )
            , upper = Nothing
            }
        )


{-| -}
gt : Value compatible -> MediaFeatureToken f -> Condition
gt =
    mediaRange Structure.Gt


{-| -}
lt : Value compatible -> MediaFeatureToken f -> Condition
lt =
    mediaRange Structure.Lt


{-| -}
ge : Value compatible -> MediaFeatureToken f -> Condition
ge =
    mediaRange Structure.Ge


{-| -}
le : Value compatible -> MediaFeatureToken f -> Condition
le =
    mediaRange Structure.Le


{-| -}
eq : Value compatible -> MediaFeatureToken f -> Condition
eq =
    mediaRange Structure.Eq


{-| Inclusive on both ends: `(a <= feature <= b)`. -}
between : Value compatibleLow -> Value compatibleHigh -> MediaFeatureToken f -> Condition
between low high token =
    Condition
        (Structure.Range
            { feature = token.value
            , lower = Just ( Structure.Le, low.value )
            , upper = Just ( Structure.Le, high.value )
            }
        )
```

`Value compatible` is already aliased at line 127-129 (`{ compatible | value : String }`). `Compatible` and `Structure` are already imported via `import Css.Structure as Structure exposing (..)` (line 80).

- [ ] **Step 6: Run tests to verify they pass**

Run: `npm test`
Expected: `mediaConditionAlgebra` and `mediaRangeComparisons` pass; entire suite green, including all pre-existing `tests/Media.elm` tests (regression).

- [ ] **Step 7: Commit**

```bash
git add src/Css/Media.elm tests/Media.elm
git commit -m "feat(media): add additive condition algebra and range comparisons

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 7: `cq*` container length units in `Css.elm`

**Files:**
- Modify: `src/Css.elm` (add units near the viewport units at 2272-2338; extend `exposing` at line 7 and `@docs` at line 368)
- Test: `tests/Container.elm` (add unit-rendering tests)

**Interfaces:**
- Consumes: `lengthConverter` (already imported at line 483) and `ExplicitLength` from `Css.Internal`.
- Produces: `cqw`, `cqh`, `cqi`, `cqb`, `cqmin`, `cqmax : Float -> ExplicitLength <tag>` and their type aliases + private unit tags. These produce full `ExplicitLength` records that already carry `absoluteLength : Compatible`, so they satisfy `Css.Container.minWidth` etc.

- [ ] **Step 1: Write failing unit tests**

Add to `tests/Container.elm`:

```elm
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
```

Requires `import Css exposing (..)` (already present in the test module).

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: compile failure — `cqw` etc. do not exist.

- [ ] **Step 3: Add the six units**

In `src/Css.elm`, after the `vmax`/`VMaxUnits` block (ends line 2338), add:

```elm
{-| [`cqw`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqw) container query width units.
-}
type alias Cqw =
    ExplicitLength CqwUnits


{-| [`cqw`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqw) container query width units.
-}
cqw : Float -> Cqw
cqw =
    lengthConverter CqwUnits "cqw"


type CqwUnits
    = CqwUnits


{-| [`cqh`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqh) container query height units.
-}
type alias Cqh =
    ExplicitLength CqhUnits


{-| [`cqh`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqh) container query height units.
-}
cqh : Float -> Cqh
cqh =
    lengthConverter CqhUnits "cqh"


type CqhUnits
    = CqhUnits


{-| [`cqi`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqi) container query inline-size units.
-}
type alias Cqi =
    ExplicitLength CqiUnits


{-| [`cqi`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqi) container query inline-size units.
-}
cqi : Float -> Cqi
cqi =
    lengthConverter CqiUnits "cqi"


type CqiUnits
    = CqiUnits


{-| [`cqb`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqb) container query block-size units.
-}
type alias Cqb =
    ExplicitLength CqbUnits


{-| [`cqb`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqb) container query block-size units.
-}
cqb : Float -> Cqb
cqb =
    lengthConverter CqbUnits "cqb"


type CqbUnits
    = CqbUnits


{-| [`cqmin`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqmin) container query min units.
-}
type alias Cqmin =
    ExplicitLength CqminUnits


{-| [`cqmin`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqmin) container query min units.
-}
cqmin : Float -> Cqmin
cqmin =
    lengthConverter CqminUnits "cqmin"


type CqminUnits
    = CqminUnits


{-| [`cqmax`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqmax) container query max units.
-}
type alias Cqmax =
    ExplicitLength CqmaxUnits


{-| [`cqmax`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#cqmax) container query max units.
-}
cqmax : Float -> Cqmax
cqmax =
    lengthConverter CqmaxUnits "cqmax"


type CqmaxUnits
    = CqmaxUnits
```

- [ ] **Step 4: Extend the `Css.elm` `exposing` list and `@docs`**

In the exposing list at line 7 (the `Length, pct, px, ... vh, vw, vmin, vmax, ...` group), add `cqw, cqh, cqi, cqb, cqmin, cqmax` (functions) after `vmax`. Do not export the type aliases/unit tags (matching how `Vw`/`VwUnits` are unexported — confirm `Vw` is not in the exposing list; it is not). In the matching `@docs` line at 368, add `cqw, cqh, cqi, cqb, cqmin, cqmax`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `npm test`
Expected: `containerUnits` passes; suite green.

- [ ] **Step 6: Commit**

```bash
git add src/Css.elm tests/Container.elm
git commit -m "feat(css): add cqw/cqh/cqi/cqb/cqmin/cqmax container query units

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 8: `Css.Global.container` / `containerQuery`

**Files:**
- Modify: `src/Css/Global.elm` (`media` at 215-261, `mediaQuery` at 280-282; module `exposing` at line 3 and `@docs` at line 31)
- Test: `tests/Container.elm` (add global-snippet tests)

**Interfaces:**
- Consumes: `Preprocess.ContainerRule` (Task 3), `Structure.QueryCondition`, `Structure.ContainerFeature`, `Structure.Raw`, and the `Css.Container.Condition` builders. Because `Css.Global.container` should accept a raw whole-condition string (mirroring `mediaQuery`'s `List String`) AND a typed condition, follow the spec: mirror `media`/`mediaQuery`. `media` takes `List MediaQuery`; the container analog takes the container condition data. Provide `container : Maybe String -> Structure.QueryCondition Structure.ContainerFeature -> List Snippet -> Snippet` is internal-flavored; instead expose a user-friendly pair mirroring `mediaQuery` (string-based) and `media` (typed). Given `Css.Container.Condition` is opaque, `Css.Global` cannot unwrap it. Resolve by having `Css.Container` expose the query-building for globals, OR by having `containerQuery` take the raw string and `container` take `List Css.Container.Condition`.

  **Decision (see ambiguity note A in the final report):** expose two functions:
  - `containerQuery : String -> List Snippet -> Snippet` — raw whole-condition string (mirrors `mediaQuery`).
  - `container : List Css.Container.Condition -> List Snippet -> Snippet` — typed, anonymous, list joined with `and` (mirrors `media`).

  For this to work, `Css.Container` must expose a way to convert `List Condition` to `Structure.QueryCondition Structure.ContainerFeature`. Add an internal-ish exposed helper to `Css.Container`: `toStructureCondition : List Condition -> Structure.QueryCondition Structure.ContainerFeature`. Reconsider during review whether to instead move `container`/`containerQuery` into `Css.Container` to avoid widening the opaque boundary. This plan keeps them in `Css.Global` (per spec "Mirror `Css.Global.media`/`mediaQuery`") and adds the helper.

- Produces (add to `Css.Global` `exposing`): `container`, `containerQuery`. And (add to `Css.Container` `exposing`): `toStructureCondition`.

- [ ] **Step 1: Write failing global tests**

Add to `tests/Container.elm`:

```elm
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
```

Add `import Css.Global` and `import Css.Container as Container` and `footer` to the test imports as needed (`Css.Global.footer` — confirm `footer` is exposed by `Css.Global`; if not, use `p`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `npm test`
Expected: compile failure — `Css.Global.container`/`containerQuery` and `Container.toStructureCondition` do not exist.

- [ ] **Step 3: Expose `toStructureCondition` from `Css.Container`**

In `src/Css/Container.elm`, add to the `exposing` list `toStructureCondition`, and add:

```elm
{-| Internal-use helper for `Css.Global.container`. Converts a list of
conditions (joined with `and`) into the underlying structure condition.
-}
toStructureCondition : List Condition -> Structure.QueryCondition Structure.ContainerFeature
toStructureCondition =
    combineAnd
```

- [ ] **Step 4: Add `container`/`containerQuery` to `Css.Global`**

In `src/Css/Global.elm`, after `mediaQuery` (ends line 282), add. Model the body on `media` (215-261): extract style blocks into a `Preprocess.ContainerRule` and recurse into nested rules. Import `Css.Container`:

```elm
{-| Combines conditions into a global `@container` rule.

    global
        [ container [ Container.minWidth (px 400) ]
            [ footer [ Css.maxWidth (px 300) ] ]
        ]

-}
container : List Css.Container.Condition -> List Snippet -> Snippet
container conditions snippets =
    containerRuleHelp Nothing (Css.Container.toStructureCondition conditions) snippets


{-| Manually specify a global `@container` rule with a raw whole-condition string.

    global
        [ containerQuery "sidebar (min-width: 400px)"
            [ footer [ Css.maxWidth (px 300) ] ]
        ]

-}
containerQuery : String -> List Snippet -> Snippet
containerQuery raw snippets =
    containerRuleHelp Nothing (Structure.Raw raw) snippets


containerRuleHelp : Maybe String -> Structure.QueryCondition Structure.ContainerFeature -> List Snippet -> Snippet
containerRuleHelp name condition snippets =
    let
        snippetDeclarations : List Preprocess.SnippetDeclaration
        snippetDeclarations =
            List.concatMap unwrapSnippet snippets

        extractStyleBlocks : List Preprocess.SnippetDeclaration -> List Preprocess.StyleBlock
        extractStyleBlocks declarations =
            case declarations of
                [] ->
                    []

                (Preprocess.StyleBlockDeclaration styleBlock) :: rest ->
                    styleBlock :: extractStyleBlocks rest

                _ :: rest ->
                    extractStyleBlocks rest

        containerRuleFromStyleBlocks : Preprocess.SnippetDeclaration
        containerRuleFromStyleBlocks =
            Preprocess.ContainerRule name condition (extractStyleBlocks snippetDeclarations)

        nestedContainerRules : List Preprocess.SnippetDeclaration -> List Preprocess.SnippetDeclaration
        nestedContainerRules declarations =
            case declarations of
                [] ->
                    []

                (Preprocess.StyleBlockDeclaration _) :: rest ->
                    nestedContainerRules rest

                (Preprocess.ContainerRule _ _ styleBlocks) :: rest ->
                    -- nested @container: outer wins, combine conditions with And
                    Preprocess.ContainerRule name condition styleBlocks
                        :: nestedContainerRules rest

                first :: rest ->
                    first :: nestedContainerRules rest
    in
    Preprocess.Snippet (containerRuleFromStyleBlocks :: nestedContainerRules snippetDeclarations)
```

Note: the nested flattening here mirrors `media`'s `nestedMediaRules`. Because `@media { @container }` nested output is out of scope (spec Nesting semantics), nested `Preprocess.MediaRule` inside a `container` snippet falls through the `first :: rest` catch-all unchanged — acceptable for v1. If a stricter and-combine of nested container conditions is desired, revisit; the spec only requires "the same nested-rule flattening `media` does," which this matches structurally.

Add imports at the top of `Css/Global.elm`: `import Css.Container` and ensure `Css.Structure as Structure` and `Css.Preprocess as Preprocess`/`unwrapSnippet` are already imported (they are, since `media` uses them).

- [ ] **Step 5: Extend `Css.Global` `exposing` and `@docs`**

In the header exposing list (line 3) add `container, containerQuery` next to `media, mediaQuery`. In the `@docs` line (line 31) add `container, containerQuery`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `npm test`
Expected: `globalContainer` and `globalContainerQuery` pass; suite green.

- [ ] **Step 7: Commit**

```bash
git add src/Css/Global.elm src/Css/Container.elm tests/Container.elm
git commit -m "feat(global): add container/containerQuery global snippet constructors

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Task 9: Compaction/extension nesting tests, hashing regression, `elm.json`, doc-tests

**Files:**
- Modify: `elm.json` (exposed-modules "Styling" at 20-26)
- Test: `tests/Container.elm` (add compaction/extension + `withMedia`⇄`withContainer` outer-wins + hashing regression tests)
- Modify: `tests/elm-doc-test.json` if it must list `Css.Container` (it lists `["Css"]` under `root: ../src`) — check whether doc-tests need the new module added.

**Interfaces:**
- Consumes: everything from Tasks 1-8.

- [ ] **Step 1: Write compaction/extension + outer-wins tests**

Add to `tests/Container.elm`:

```elm
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
```

Requires `import Css.Media as Media exposing (only, screen)` in the test module. Adjust the exact expected selector output for `containerSelectorExtension` after observing the failing run — the child-combinator rendering (`p > a`) follows `selectorToString`; if the pipeline emits `p>a` without spaces, match that. Confirm the real output and set the expectation to it (do not guess — run and read).

- [ ] **Step 2: Write the class-name hashing regression test**

The class name is `Hash.fromString cssTemplate` over the rendered CSS. Two `withContainer` styles differing only in condition produce different CSS templates, hence different hashes. Assert this end-to-end via `Html.Styled`. Add to `tests/Container.elm` (or a new `tests/ContainerHash.elm` if imports get heavy):

```elm
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
```

Rationale: because the class-name hash in `VirtualDom/Styled.elm` (line 754) is `Hash.fromString` of the CSS template, distinct CSS text guarantees distinct class names. Asserting the CSS text differs is the load-bearing regression. If a stronger assertion through the `Html.Styled` classname path is wanted, add a test that renders two elements and asserts distinct `class` attributes; note this requires importing `Html.Styled` and inspecting rendered attributes, which is heavier — the CSS-text assertion is sufficient and is what the spec's "distinct classes" reduces to.

- [ ] **Step 3: Run the new tests to verify they fail (where applicable) then pass**

Run: `npm test`
Expected: the extension test may need its expected string corrected to match real output (iterate: run, read the actual, set expectation, re-run). `withMediaContainerOuterWins` and `containerHashDistinct` should pass against Task 3/4 behavior. If `withMediaContainerOuterWins` fails, the `toMediaRule` `ContainerRule` case from Task 4 Step 4 is the fix location.

- [ ] **Step 4: Add `Css.Container` to `elm.json`**

In `elm.json`, in `"Styling"` (lines 20-26), add `"Css.Container"`:

```json
        "Styling": [
            "Css",
            "Css.Animations",
            "Css.Transitions",
            "Css.Media",
            "Css.Container",
            "Css.Global"
        ]
```

- [ ] **Step 5: Verify doc-tests and public docs**

Every exposed function in `Css.Container` needs a doc comment (the module `@docs` block references them — Elm's doc build fails if any exposed value is missing from `@docs`). Confirm each exposed name appears in a `@docs` line and has a `{-| ... -}` comment. Run the doc build:

Run: `npx elm make --docs=/tmp/docs.json`
Expected: succeeds with no "missing docs" errors for `Css.Container`, `Css.Media`, `Css.Global`, `Css`.

If `tests/elm-doc-test.json` should exercise `Css.Container` doc examples, add `"Css.Container"`, `"Css.Media"`, `"Css.Global"` to its `"tests"` array (currently `["Css"]`). Only add modules whose doc comments contain runnable example code blocks; the `Css.Container` examples above are illustrative snippets, not `elm-verify-examples` blocks, so this may be a no-op — verify against how `tests/Media.elm`/existing doc-tests are configured before editing.

- [ ] **Step 6: Run the full suite + doc build one final time**

Run: `npm test && npx elm make --docs=/tmp/docs.json`
Expected: all tests pass; docs build clean.

- [ ] **Step 7: Commit**

```bash
git add elm.json tests/Container.elm tests/elm-doc-test.json
git commit -m "feat(container): add to exposed-modules; nesting, hashing, and doc tests

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes (spec coverage map)

- Shared `QueryCondition`/`Range`/`RangeExpression`/`Comparison` in `Css.Structure` → Task 1.
- `ContainerRule` declaration + compaction/extension cases → Task 1 (steps 6-9).
- `ConditionQuery` on `MediaQuery` → Task 1 (step 3), Output → Task 2 (step 5).
- `Css.Structure.Output` serialization incl. parenthesization + range forms → Task 2.
- `Css.Preprocess` `WithContainer` variant + snippet declaration → Task 3.
- `Css.Preprocess.Resolve` resolution + documented nesting semantics → Task 4.
- Public `Css.Container` (rule constructors, combinators, min/max, feature tokens, gt/lt/ge/le/eq/between, dual-role `inlineSize`, orientation, establishment properties) → Task 5.
- Additive `Css.Media` API (Condition/expr/anyOf/allOf/inverse/condition + six comparisons via `mediaFeature`) → Task 6.
- `cq*` units following `vw` pattern → Task 7.
- `Css.Global.container`/`containerQuery` → Task 8.
- `elm.json` exposed-modules + testing checklist + hashing regression → Task 9.
