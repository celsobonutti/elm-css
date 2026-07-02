# Container Queries (`@container`) for elm-css — Design

**Date:** 2026-07-01 (amended 2026-07-02: typed range syntax added)
**Status:** Approved.
**Supersedes:** `2026-06-30-container-queries-design.md` (removed; this session's
decisions replace it in full).

## Goal

Add end-to-end support for CSS [container queries](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@container)
through a new `Css.Container` module modeled on `Css.Media`, covering:

1. The `@container` at-rule (typed size queries including range syntax, named
   containers, escape hatches).
2. The container establishment properties: `container-type`, `container-name`,
   and the `container` shorthand.
3. The container query length units: `cqw`, `cqh`, `cqi`, `cqb`, `cqmin`, `cqmax`.
4. A typed `and`/`or`/`not` condition grammar, also mirrored **additively** into
   `Css.Media` — every existing `Css.Media` function, type, and output stays
   unchanged; only new functions are added. This lands as a minor version bump.

Out of scope (YAGNI for this pass; the escape hatches cover them):

- Typed `style()` queries (`@container style(--accent: blue)`).
- Typed `scroll-state()` queries.
- Nested at-rule output (`@media { @container { … } }`) — see Nesting semantics.

## Architecture

Follow the `@media` pipeline exactly; each `@media` touch-point gets a parallel
`@container` touch-point. All internal modules (`Css.Structure`, `Css.Preprocess`,
`Css.Preprocess.Resolve`, `Css.Structure.Output`) are **not** in `elm.json`'s
exposed-modules, so internal changes carry no compatibility constraint.

| Layer | `@media` today | `@container` addition |
|---|---|---|
| Public API | `Css.Media` | new `Css.Container` |
| Preprocess (`Style`) | `WithMedia (List MediaQuery) (List Style)` | `WithContainer (Maybe String) (QueryCondition ContainerFeature) (List Style)` |
| Structure (`Declaration`) | `MediaRule (List MediaQuery) (List StyleBlock)` | `ContainerRule (Maybe String) (QueryCondition ContainerFeature) (List StyleBlock)` |
| Resolve | `resolveMediaRule`, `toMediaRule`, `styleBlockToMediaRule` | matching `resolveContainerRule`, `toContainerRule`, `styleBlockToContainerRule` |
| Structure compaction | `MediaRule` cases in `extendLastSelector`, `concatMapLastStyleBlock`, `compactHelp` | matching `ContainerRule` cases |
| Output | `@media …` | `@container [name ]<condition> { … }` |
| Global | `Css.Global.media` / `mediaQuery` | `Css.Global.container` / `containerQuery` |

An alternative — generalizing `Declaration` so at-rules hold nested
`Declaration`s (enabling `@media { @container { … } }`) — was considered and
deferred: it is a large, risky refactor of `Resolve.elm`, and sibling
`withMedia`/`withContainer` styles on one element cover the common cases. It is
the named future fix for the nesting limitation below.

## The shared condition tree (`Css.Structure`)

One generic tree, parameterized by leaf type so each public module gets its own
feature vocabulary:

```elm
type QueryCondition leaf
    = Feature leaf                        -- (min-width: 400px), (orientation: landscape)
    | Range RangeExpression               -- (width > 400px), (200px <= width <= 700px)
    | Not (QueryCondition leaf)           -- not (…)
    | And (List (QueryCondition leaf))    -- (…) and (…)
    | Or (List (QueryCondition leaf))     -- (…) or (…)
    | Raw String                          -- escape hatch, emitted verbatim

type alias ContainerFeature =
    { feature : String, value : Maybe String }   -- same shape as MediaExpression

{-| A range feature test. `lower`/`upper` are the optional bounds:
gt/lt/ge/le/eq set exactly one; between sets both (inclusive, Le/Le). -}
type alias RangeExpression =
    { feature : String
    , lower : Maybe ( Comparison, String )
    , upper : Maybe ( Comparison, String )
    }

type Comparison
    = Lt | Le | Gt | Ge | Eq
```

`Range` is leaf-independent, so both `Css.Container` and `Css.Media` conditions
can hold ranges.

New `Declaration` variant:

```elm
| ContainerRule (Maybe String) (QueryCondition ContainerFeature) (List StyleBlock)
```

New `MediaQuery` variant (invisible to users — `Css.Media.MediaQuery` is exposed
without constructors):

```elm
| ConditionQuery (QueryCondition MediaExpression)
```

### Output (`Css.Structure.Output`)

`conditionToString`:

- `Feature f` → `(feature: value)` or `(feature)` (reuse the
  `mediaExpressionToString` logic).
- `Range r` → single bound emits feature-first: `(width > 400px)`,
  `(width = 400px)`; both bounds emit the chained form:
  `(200px <= width <= 700px)`.
- `Not c` → `not ` ++ parenthesized child.
- `And cs` / `Or cs` → children joined with ` and ` / ` or `.
- `Raw s` → `s` verbatim.

**Parenthesization:** `Feature` emits its own parens. Composite children
(`And`/`Or`/`Not`) nested inside another composite are always wrapped in an
extra pair of parens. CSS forbids mixing `and`/`or`/`not` at one level without
grouping; the tree makes that unrepresentable and the always-parenthesize rule
keeps output valid, e.g.
`@container ((min-width: 400px) or (not (orientation: landscape))) { … }`.

`ContainerRule` emission: `"@container "` ++ optional `name ++ " "` ++ condition
++ `"{"` ++ blocks ++ `"}"`. `ConditionQuery` emission inside a media query
list: the condition string, comma-joined with sibling queries as usual.

**Hashing checkpoint:** verify the generated class-name hash (murmur3)
incorporates the new `Preprocess`/`Structure` variants so two elements differing
only in container condition get distinct classes. Add a regression test.

## `Css.Container` public API

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
    )
```

`Condition` is opaque, wrapping `Structure.QueryCondition ContainerFeature`.

### Rule constructors

```elm
withContainer : List Condition -> List Style -> Style
-- top-level list is joined with `and`
-- withContainer [ minWidth (px 400), orientation landscape ] [ … ]
-- ⇒ @container (min-width: 400px) and (orientation: landscape) { ._hash { … } }

withContainerNamed : String -> List Condition -> List Style -> Style
-- withContainerNamed "sidebar" [ minWidth (px 400) ] [ … ]
-- ⇒ @container sidebar (min-width: 400px) { … }

withContainerQuery : String -> List Style -> Style
-- raw whole-condition escape hatch, mirrors withMediaQuery
```

Container names are plain `String`s, documented as needing to be valid CSS
custom-idents; no validation in v1.

### Combinators

```elm
anyOf : List Condition -> Condition        -- (a) or (b) or (c)
allOf : List Condition -> Condition        -- (a) and (b) — for nesting inside anyOf
not : Condition -> Condition               -- not (a); shadows Basics.not, precedent: Css.Media.not
rawCondition : String -> Condition         -- composable escape hatch,
                                           -- e.g. rawCondition "style(--theme: dark)"
```

### Features

All length arguments use the `AbsoluteLength compatible` constraint from
`Css.Media`. `aspect-ratio` features reuse the `Ratio` pattern
(`Css.Media.ratio`-style constructor, defined locally).

**Min/max-prefixed features** return `Condition` directly, mirroring `Css.Media`:
`minWidth`, `maxWidth`, `minHeight`, `maxHeight`, `minInlineSize`,
`maxInlineSize`, `minBlockSize`, `maxBlockSize`, `minAspectRatio`,
`maxAspectRatio`.

**There are intentionally no exact-match plain features** (`width (px 400)` →
`(width: 400px)`): those names belong to the range-syntax feature tokens below,
and exact match is expressed as `width |> eq (px 400)` → `(width = 400px)`,
which is semantically equivalent.

`orientation` takes local `Landscape`/`Portrait`/`landscape`/`portrait` values —
structurally identical to `Css.Media`'s records, so values from either module
work, but `Css.Container` is self-contained (no second import needed).

### Range syntax: feature tokens + comparisons

Feature tokens are compatibility records in the classic elm-css keyword style:

```elm
width : { value : String, containerFeature : Compatible, mediaFeature : Compatible }
-- likewise height, aspectRatio (shared with media queries);
-- inlineSize, blockSize carry containerFeature but NOT mediaFeature
-- (container-only features);
-- inlineSize ALSO carries containerTypeValue — see Establishment properties.
```

Comparison builders are value-first so pipelines read feature-first:

```elm
gt, lt, ge, le, eq : Value compatible -> FeatureToken f -> Condition
between : Value compatible -> Value compatible -> FeatureToken f -> Condition
-- where FeatureToken f = { f | value : String, containerFeature : Compatible }

withContainer [ width |> gt (px 400) ] [ … ]
-- ⇒ @container (width > 400px) { … }

withContainer [ width |> between (px 200) (px 700) ] [ … ]
-- ⇒ @container (200px <= width <= 700px) { … }

withContainer [ aspectRatio |> ge (ratio 16 9) ] [ … ]
-- ⇒ @container (aspect-ratio >= 16/9) { … }
```

`between` is inclusive on both ends (`<=` twice). Comparison values use the
loose `Value compatible = { compatible | value : String }` alias so lengths and
ratios both fit; per-feature value checking (e.g. rejecting a ratio on `width`)
is not attempted in v1.

### Establishment properties

Housed in `Css.Container` so one import covers the whole feature:

```elm
containerType : ContainerTypeValue a -> Style
normal : …    -- container-type: normal
size : …      -- container-type: size
-- inline-size: use the dual-role `inlineSize` token (see below)

containerName : String -> Style          -- container-name: sidebar
containerNames : List String -> Style    -- container-name: a b

container : String -> ContainerTypeValue a -> Style
-- shorthand: container "sidebar" inlineSize ⇒ container: sidebar / inline-size
```

`ContainerTypeValue a` follows the existing extensible keyword-record pattern
(`{ a | value : String, containerTypeValue : Compatible }`). The `inlineSize`
token carries **both** the `containerFeature` and `containerTypeValue` markers,
so one export serves both roles: `containerType inlineSize` and
`inlineSize |> gt (px 400)` both compile, and neither `normal`/`size` nor the
other feature tokens cross over (they each carry only their own marker).

## `Css.Media` additive additions

Media's existing feature functions return `Expression` — a public record alias
that cannot change — so Media needs an explicit lift into the algebra. Media
gets its **own** opaque `Condition` (wrapping
`Structure.QueryCondition MediaExpression`); the two modules' `Condition` types
are deliberately distinct so the compiler rejects media features in `@container`
queries and container features in `@media` queries.

```elm
-- New in Css.Media; nothing existing changes:
type Condition                             -- opaque
expr : Expression -> Condition             -- lift an existing feature
anyOf : List Condition -> Condition
allOf : List Condition -> Condition
inverse : Condition -> Condition           -- `not` is taken by media-type negation
condition : List Condition -> MediaQuery   -- top-level list joined with `and`

gt, lt, ge, le, eq : Value compatible -> MediaFeatureToken f -> Condition
between : Value compatible -> Value compatible -> MediaFeatureToken f -> Condition
-- where MediaFeatureToken f = { f | value : String, mediaFeature : Compatible }
```

The range comparisons reuse the feature tokens from `Css.Container` (the
canonical token home): shared tokens (`width`, `height`, `aspectRatio`) carry
the `mediaFeature` marker, so `Container.width |> Media.gt (px 600)` compiles,
while container-only tokens (`inlineSize`, `blockSize`) lack it and are
rejected by the compiler in media conditions. None of `gt`/`lt`/`ge`/`le`/
`eq`/`between` clash with existing `Css.Media` names.

```elm
withMedia
    [ condition
        [ expr (minWidth (px 400))
        , anyOf [ expr landscape, inverse (expr (hover canHover)) ]
        ]
    ]
    [ … ]
-- ⇒ @media (min-width: 400px) and ((orientation: landscape) or (not (hover: hover))) { … }

withMedia [ condition [ Container.width |> gt (px 600) ] ] [ … ]
-- ⇒ @media (width > 600px) { … }
```

Because `condition` returns a `MediaQuery`, it slots into `withMedia`'s existing
comma-separated query list and composes freely with `all`/`only`/`not` queries.
The `expr` lift is slightly verbose; or/not media queries are the rare case and
the trade is worth keeping every existing signature stable. Names
`expr`/`inverse`/`condition` are final unless review says otherwise.

## `Css.elm` additions — container length units

`cqw`, `cqh`, `cqi`, `cqb`, `cqmin`, `cqmax : Float -> …`, each following the
exact `vw`/`vh` implementation pattern (type alias + `lengthConverter` + private
units tag), placed alongside the viewport units. Usable anywhere a length is,
including inside styles under `withContainer`. Purely additive.

## `Css.Global` additions

Mirror `Css.Global.media`/`mediaQuery` with `container`/`containerQuery` snippet
constructors producing the new snippet declaration, including the same
nested-rule flattening `media` does.

## Nesting semantics (documented v1 behavior)

- `withContainer` inside `withContainer`: conditions and-combine into a single
  rule; the inner name wins when both are named.
- `withContainer` inside `withMedia` (or vice versa): the **outer** rule applies
  and the inner condition is dropped — the same structural limitation nested
  media queries have today (`MediaRule` holds `List StyleBlock`, not
  declarations). Documented as a known limitation; the future fix is the
  deferred at-rules-hold-`Declaration`s refactor. The recommended pattern —
  sibling `withMedia […] […]` and `withContainer […] […]` styles on one
  element — is unaffected.

## Testing

New `tests/Container.elm` mirroring `tests/Media.elm`:

- Each feature → expected `@container (…)` output.
- Range comparisons: each of `gt`/`lt`/`ge`/`le`/`eq` → expected operator
  output; `between` → chained `(a <= f <= b)` form; ranges on `aspectRatio`
  with `ratio` values; dual-role `inlineSize` in both positions.
- Combinator composition and nested parenthesization (`anyOf`/`allOf`/`not`,
  including `not` directly under `anyOf`, and ranges under combinators).
- Named vs anonymous containers; `withContainerNamed` output.
- `withContainerQuery` and `rawCondition` passthrough.
- Nesting: `withContainer` inside a selector, selectors extended inside
  `withContainer` (compaction cases), nested `withContainer` and-combining,
  and the documented `withMedia`⇄`withContainer` outer-wins behavior.
- Properties: `containerType`/`containerName`/`containerNames`/`container`
  shorthand render correctly.
- Units: `cqw`…`cqmax` render correctly.
- `Css.Global.container` output.
- `Css.Media` additions: `condition`/`expr`/`anyOf`/`allOf`/`inverse` output,
  and range comparisons with shared `Css.Container` tokens.
- Regression: existing `withMedia` output is byte-identical to before;
  class-name hashing distinguishes styles differing only in container condition.

Add doc-test entries for new exposed functions and add `Css.Container` to
`elm.json`'s exposed-modules (under "Styling").

## Implementation order

1. `Css.Structure`: `QueryCondition` (incl. `Range`/`RangeExpression`/
   `Comparison`), `ContainerFeature`, `ContainerRule`, `ConditionQuery`;
   compaction cases; `styleBlockToContainerRule`.
2. `Css.Structure.Output`: `conditionToString` (incl. range forms),
   `@container` emission, `ConditionQuery` emission.
3. `Css.Preprocess`: `WithContainer` variant + snippet declaration; handle in
   existing `case style of` sites.
4. `Css.Preprocess.Resolve`: `resolveContainerRule`, `WithContainer` fold case,
   nesting semantics.
5. `Css.Container`: public module (queries + tokens/comparisons + properties).
6. `Css.Media`: `Condition`/`expr`/`anyOf`/`allOf`/`inverse`/`condition` +
   `gt`/`lt`/`ge`/`le`/`eq`/`between`.
7. `Css.elm`: `cqw`…`cqmax`.
8. `Css.Global`: `container`/`containerQuery`.
9. `elm.json` exposed-modules; tests throughout (test-first per module).
