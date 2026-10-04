# zucbor — Design

**Status:** Draft, 2026-09-30. Nothing here is implemented yet. This is the specification; amend it in the same commit as the code that changes it.
**Package:** `zucbor`
**One line:** Deterministic CBOR (RFC 8949) encoding and validating, limit-bounded decoding between raw vectors and ordinary R values, vendoring TinyCBOR.

Every statement here is a decision. Things not yet decided live in §19 and nowhere else. [roadmap.md](roadmap.md) sequences the work; its section references (§) point here.

---

## 1. What zucbor is

A CBOR library for R that:

- decodes CBOR from raw vectors, files and connections into ordinary R vectors and lists;
- **checks the whole input before building any R object**, and bounds that check with limits, because the input is expected to be hostile (network peers, IoT devices, authenticators);
- encodes R values to CBOR **deterministically**: identical R objects always produce identical bytes;
- represents what R has no native type for (non-text map keys, tags, wide integers, simple values) with small classed objects rather than by guessing;
- installs from source everywhere R does, with no system library.

It is the fourth self-describing format in a family with `zujson`, `zuyaml` and `zuxml`. The R mapping follows `zujson` wherever CBOR's data model is JSON's (CBOR is JSON's binary counterpart); it departs only where CBOR carries something JSON cannot, and each departure is argued below.

Target uses, which decide the edge cases:

- **COSE** (RFC 9052) and **CWT** (RFC 8392) — maps with integer keys, byte strings, tags, and a signature computed over a deterministic encoding;
- **WebAuthn / passkeys** — the attestation object and COSE_Key inside `authData`, decoded from bytes a browser handed over;
- **CoAP device telemetry** and SenML — many small records, often as a CBOR sequence (RFC 8742);
- other IETF protocols that moved from JSON to CBOR.

Design principle:

> `cbor_decode()` returns the value the bytes encode, not an interpretation of it. Where R cannot hold a value faithfully, the result says so in its class; it never silently changes the value.

---

## 2. Scope

| | v1 | Phase 2 | Never |
|---|---|---|---|
| Decode raw / file / connection | yes | | |
| CBOR sequences (RFC 8742) | yes | | |
| Validation (`cbor_validate()`) | yes | | |
| Deterministic encoding (RFC 8949 §4.2.1) | yes, always on | | a non-deterministic mode |
| Deterministic-input check on decode | yes, opt-in | | |
| Indefinite-length items on decode | yes | | on encode |
| Tags: dates, bignums, self-describe | yes, converted | UUID (37), URI (32) | |
| Unknown tags | yes, as `cbor_tag` | registered handlers | |
| Non-text map keys | yes, as `cbor_map` | | stringified by default |
| Diagnostic notation (`cbor_diagnose()`) | yes, output only, as RFC 8949 Appendix A writes it | | parsing diagnostic notation |
| Data frames | | row-oriented, as `zujson` | |
| CTAP2 canonical key order (length-first) | | yes, if a caller needs it (§19) | as the default |
| Streaming / incremental decode | | | yes — see §9 |
| Public C API / static archive | | only once a caller exists | |
| Base64 / base64url, COSE crypto, CDDL validation | | | yes — other packages' concerns |

The package decodes and encodes CBOR. It does not verify signatures, parse CDDL, or know what a COSE header means.

---

## 3. Why TinyCBOR

- C99, MIT licensed, no dependencies, a dozen small files;
- a **non-allocating** parser and encoder on the paths used here: it works in the caller's buffer, so every byte of heap state is ours to own (§12);
- `cbor_value_validate()` covers UTF-8 validity and the canonical-form checks as one audited function, and its iterator reports well-formedness faults with their positions;
- it is maintained — 7.0 (2026-02) carries fixes from outside security review — and small enough to audit.

What it does **not** give us, so the package must:

- **Limits.** Its only bound is the compile-time recursion cap `CBOR_PARSER_MAX_RECURSIONS` (1024, which admits 1023 levels; §11). Depth, size and item limits are ours (§11).
- **Duplicate-key detection in unsorted maps.** `CborValidateMapKeysAreUnique` compares neighbours, so it detects duplicates only in a map already sorted. Detection is ours (§6.5).
- **Error positions.** `cbor_value_validate()` takes a `const CborValue *` and returns a status only. Offsets come from our own walk (§10).
- **Correct tag-content rules.** `CborValidateTagUse` checks a table that allows only an integer under tag 1, where RFC 8949 §3.4.2 also allows a float, so it refuses Appendix A's `1(1363896240.5)`; the same table refuses anything but a byte string, array or map under tags 21–23, which RFC 8949 §3.4.5.2 lets wrap any item. The walk checks tag content instead (§11), found at Stage 2; reported as [intel/tinycbor#339](https://github.com/intel/tinycbor/issues/339).
- **Semantic tag conversion**, and **the encoder**. Deterministic encoding sorts map entries by their encoded keys, so each key's bytes must be produced, sorted and spliced into the output. TinyCBOR's encoder counts every container's items and has no call that appends bytes it did not produce, so `cbor_encoder_close_container()` would fail with `CborErrorTooFewItems`. zucbor encodes in project code (§8), and `cborencoder.c` is not vendored (decided at Stage 4).

---

## 4. Architecture

```text
 raw | file | connection
          │   read bounded by max_size (§11); nothing unbounded is ever read
          ▼
 ┌─────────────────────────┐
 │ CHECK   (no R objects)  │  zu_walk: iterative; depth, items, duplicate keys,
 │                         │           offsets, deterministic-input rules
 │                         │  cbor_value_validate(): well-formedness, UTF-8, tag types
 └───────────┬─────────────┘
             │  known: the item is valid, depth ≤ max_depth, items ≤ max_items,
             │         and every container's length is backed by real bytes
             ▼
 ┌─────────────────────────┐
 │ BUILD                   │  zu_build: recursive (bounded by max_depth);
 │                         │  preallocates from checked counts; §6 mapping
 └───────────┬─────────────┘
             ▼
        R value
```

Three rules follow from this and are non-negotiable:

1. **No R object is allocated until the check phase has passed over the whole item.** A CBOR header can claim 2^64 elements in nine bytes. Because every element costs at least one input byte and the check phase has walked all of them, the build phase can never be asked to allocate for elements that are not in the input.
2. **`cbor_validate(x)` is exactly the check phase of `cbor_decode(x)`.** Same code, same flags, same limits. The two disagree only where R cannot hold a valid value (§6.8), never about the bytes.
3. **The build phase trusts the check phase and nothing else.** It still checks every TinyCBOR return code, since TinyCBOR's preconditions are `cbor_assert()`s that become undefined behaviour under R's `-DNDEBUG` (§13, trap 3).

The encoder is a separate path with its own two passes (§8).

---

## 5. Public R API (complete v1 surface)

```r
# decode
cbor_decode(x, ...)          # raw -> R value; exactly one data item
cbor_decode_seq(x, ...)      # raw -> list; an RFC 8742 sequence of zero or more items
cbor_decode_prefix(x, ...)   # raw -> list(value, consumed); the item x starts with (Stage 11)
cbor_read(file, ...)         # path or connection -> R value
cbor_read_seq(file, ...)     # path or connection -> list
cbor_validate(x, sequence = FALSE, ..., error = FALSE)  # raw -> TRUE/FALSE; the check phase only
cbor_diagnose(x, sequence = FALSE, ...)  # raw -> character(1), RFC 8949 §8 diagnostic notation
cbor_annotate(x, sequence = FALSE, ...)  # raw -> cbor_annotation: annotated hex dump (Stage 13)

# encode
cbor_encode(x, ...)          # R value -> raw
cbor_encode_seq(x, ...)      # list -> raw; each element one item of a sequence

# values R has no native type for
cbor_map(keys, values)       # map with arbitrary keys
cbor_tag(tag, value)         # tagged item
cbor_simple(value)           # simple value other than false/true/null/undefined
cbor_bigint(x)               # integer outside what a double holds exactly

# classes of your own (Stage 10)
as_cbor(x, ...)              # S3 generic cbor_encode() calls for a class it does not know

zucbor_info()                # TinyCBOR version, compiled limits, defaults
```

Sixteen functions: thirteen from Stages 0–9, and `as_cbor()`, `cbor_decode_prefix()` and `cbor_annotate()` from Stages 10–13, plus `print`, `format` and `as.character` methods for the four classes, `length` for `cbor_map`, and `as.numeric` and `[` for `cbor_bigint`.

**Why `decode`/`encode`, not `parse`/`write`.** The siblings' verbs are for text formats. RFC 8949 speaks of encoders and decoders, and so do the protocols this package serves; a user reading COSE code in another language will look for those words.

**`cbor_diagnose()`** checks the input exactly as `cbor_validate()` does, then prints RFC 8949 §8 diagnostic notation. The printer is project code (`src/zu_diag.c`), not TinyCBOR's `cborpretty.c`, which always marks a float's width (`1.5f16`, or `1.5_1`) and has no flag to leave it out. It matches RFC 8949 Appendix A's own column on 79 of 81 rows. The other two are bignums, whose *value* the table shows where the notation is the tag (`2(h'010000000000000000')`). Numbers print as JavaScript's `Number.prototype.toString()` does (shortest round-trip digits; fixed notation from 1e-7 to 1e21, else an exponent), with `.0` added to a float that would read as an integer. Text is ASCII with JSON escapes, `\u` for everything past it and surrogate pairs above U+FFFF, which is also what makes the output safe on a non-UTF-8 console. The same printer names non-text keys under `map_keys = "string"`. Decided at Stage 5.

**`cbor_annotate()`** (Stage 13) checks the input as `cbor_diagnose()` does, then prints one line per head and per 16 bytes of string content: the 0-based decimal offset (as conditions report it), the bytes in hex indented by depth, and a description (`map(2)`, `negative(-501)`, `float16 1.5`, `tag(1)`, a string's first 32 bytes as diagnostic notation). Every input byte appears exactly once in the hex column, which the tests check over Appendix A and the whole COSE corpus. It is project code beside the diagnostic printer in `src/zu_diag.c`, sharing its number and string formatting; because the input is checked, it reads heads by hand rather than through TinyCBOR's iterator, which keeps chunk and break bytes in their own lines. Indentation stops at 16 levels and previews at 32 bytes, so each line is bounded and the output is a constant multiple of the input. C returns offsets, hex and descriptions; R aligns the columns. The result is a character vector of class `cbor_annotation` that prints as its lines.

**Why there is no `cbor_write()`.** `writeBin(cbor_encode(x), path)` is the whole of it. `cbor_read()` exists because reading has to be bounded before the bytes reach memory (§11); writing has no such concern.

### Decode arguments

```r
cbor_decode(
  x,
  simplify       = c("preserve", "none"),
  map_keys       = c("auto", "map", "string"),
  tags           = c("convert", "keep"),
  big_integers   = c("bigint", "double", "error"),
  duplicate_keys = FALSE,
  deterministic  = FALSE,
  max_depth      = 256L,
  max_size       = 64 * 1024^2,
  max_items      = 1e6,
  tag_handlers   = NULL    # Stage 10: list("37" = function(value) ...), §6.6
)
```

`cbor_decode_seq()`, `cbor_decode_prefix()`, `cbor_read()`, `cbor_read_seq()` take the same arguments. `cbor_validate()` and `cbor_diagnose()` take `deterministic`, `duplicate_keys` and the three limits; the mapping arguments have no meaning for them. `cbor_validate(error = TRUE)` raises the fault's classed condition (§10) instead of returning `FALSE`, so a caller can learn *why* without building the value; added at Stage 2, when the tests needed exactly that.

`x` must be a raw vector. A character string is refused with `zucbor_invalid_argument`: CBOR is bytes, and a string would need an encoding decision that has no right answer. `file` is a path, a URL, or a connection (§9).

`cbor_decode()` requires **exactly one** item. Trailing bytes are `zucbor_parse_error` (`CborErrorGarbageAtEnd`), and an empty input is `zucbor_parse_error` too — `NULL` is a legitimate decoded value (`0xf6`), so "no item" must not look like it. `cbor_decode_seq()` returns a list of however many items the bytes hold, including `list()` for empty input. This is `zuyaml`'s one-document-versus-stream rule.

`cbor_decode_prefix()` (Stage 11) is the third case: one item at the start of `x`, for CBOR inside binary framing (a COSE key inside WebAuthn `authData`, a payload after a CoAP header). It returns `list(value, consumed)`. The check phase stops after the first item (`zu_check_opts.prefix`), and nothing after it is read, not even by TinyCBOR, which preparses nothing past a top-level item; so the rest is neither checked nor trusted, and may be anything. `max_size` still applies to `x` as a whole, which is in memory already. An empty `x`, or an item cut short, is `zucbor_parse_error`. The fuzz target holds two invariants for it: an input that passes as one item passes as a prefix consuming every byte, and a prefix consuming n bytes passes as one item over those n.

### Encode arguments

```r
cbor_encode(
  x,
  auto_unbox    = TRUE,
  self_describe = FALSE,   # prefix tag 55799 (0xd9d9f7)
  max_depth     = 256L
)
```

There is no argument that turns determinism off, and no argument that changes it (§8).

---

## 6. CBOR to R

### 6.1 Scalars

| CBOR | R |
|---|---|
| unsigned / negative integer | `integer`, `double` or `cbor_bigint`, by range (§6.2) |
| half / single / double float | `double`, exactly; NaN is `NaN` |
| `false` / `true` | `logical` |
| `null`, `undefined` | `NULL` alone, `NA` inside an atomic vector |
| byte string | `raw` |
| text string | `character`, marked UTF-8 |
| other simple value (0–19, 32–255) | `cbor_simple` |
| tag | §6.6 |

Indefinite-length strings are joined; the chunking is not observable in R.

`undefined` decoding like `null` is a deliberate lossy mapping (§7.4). R has one missing value; a second one that nobody can tell apart from the first in practice would be a class every consumer has to handle for no benefit.

### 6.2 Integers

R's `integer` is 32-bit and `NA_INTEGER` is `INT_MIN`. CBOR integers span −2^64 … 2^64−1.

| value | result |
|---|---|
| −2^31 < v ≤ 2^31−1 | `integer` |
| \|v\| ≤ 2^53, otherwise | `double` (exact) |
| beyond 2^53 | per `big_integers` |

```r
big_integers = "bigint"   # default: cbor_bigint, exact
big_integers = "double"   # nearest double, an explicit opt-in to loss
big_integers = "error"    # zucbor_unrepresentable
```

`-2147483648` is a `double`, since as an `integer` it would be `NA` (the `zujson` rule).

The invariant, shared with `zuyaml`:

> Never silently lose integer precision.

`zujson` answers the other way (nearest double) and says why: a wide integer in an HTTP body is usually an identifier nobody computes with. In CBOR it is as often a nonce, a counter or a nanosecond timestamp — and the whole point of the format over JSON is that such values are exact. So the default here is `zuyaml`'s.

`cbor_bigint` is a character vector holding the **canonical decimal** (no leading zeros, `-` only for negatives, no `+`), not the source bytes. It ships with `format`, `print`, `as.character`, `as.numeric` and `[` methods and a validating constructor. Tags 2 and 3 decode by **value** through the same ladder: `2(h'01')` is `1L`, and only a bignum beyond 2^53 is a `cbor_bigint` (or a double, or an error, by `big_integers`). So an integer is one R value however it was encoded, which is what duplicate-key comparison by value (§6.5) already assumes.

### 6.3 Arrays and the simplification lattice

Arrays follow `zujson`'s `"preserve"` lattice, extended by the kinds CBOR adds:

```text
numbers:         null < integer < double
booleans:        logical, compatible only with null
wide integers:   integer-valued items + any cbor_bigint -> cbor_bigint
strings:         character, compatible only with null
classed scalars: all POSIXct -> POSIXct; all Date -> Date
everything else (raw, cbor_simple, cbor_tag, cbor_map, nested arrays and maps,
                 booleans with numbers, a mix of kinds) -> list
empty, or all null -> logical
one element that simplifies -> marked I()
```

| CBOR | R |
|---|---|
| `[1, 2, 3]` | `integer` |
| `[1, 2.5]` | `double` |
| `[1, 18446744073709551615]` | `cbor_bigint` |
| `[1.5, 18446744073709551615]` | `list` — a float is not integer-valued by kind |
| `["a", null]` | `c("a", NA)` |
| `[h'01', h'02']` | `list` of two `raw` |
| `[1(0), 1(60)]` | `POSIXct` of length 2 |
| `[1, "a"]` | `list` |
| `[]`, `[null]` | `logical(0)`, `I(NA)` |
| `[true, 1]` | `list(TRUE, 1L)` |
| `[true, null]` | `c(TRUE, NA)` |
| `[1]` | `I(1L)` |

A **float** and an **integer-valued double** are different kinds for the `cbor_bigint` rule, because the lattice must not decide from a value's magnitude what type its neighbours become. `[1.0, 2^64−1]` is a list; `[1, 2^64−1]` is a `cbor_bigint`.

**Booleans are not numbers.** `zujson` lets logical join the numeric family (`[true, 1]` is `integer`), but here that would turn `false` into `0`, which is an interpretation of the bytes, not the value they encode (§1). Decided at Stage 4, when the round-trip property test found `[false, 1.5]` re-encoding as `[0, 1.5]`.

**A one-element array is marked `I()`.** Without it `[x]` decodes to a length-one vector, which `cbor_encode()` unboxes to a bare `x`: every one-element array would silently lose its brackets on re-encoding. That matters for signed protocol data, where WebAuthn's `x5c` is often one certificate in an array. `I()` is the same marker the encoder already honours, so decode → encode is a fixed point. Also decided at Stage 4, by the same property test.

`simplify = "none"` makes every array a list. `"coerce"` (`zujson`'s third mode) is not offered: CBOR has fewer stringly-typed producers than JSON, and the mode can be added without a break.

### 6.4 Maps

```r
map_keys = "auto"    # default
map_keys = "map"     # always cbor_map
map_keys = "string"  # stringify every key into a name — lossy, opt-in
```

Under `"auto"`, a map becomes a **named list** when that is a faithful representation, and a `cbor_map` otherwise. Faithful means every key is a text string, non-empty, and unique. So:

- `{"a": 1, "b": 2}` → `list(a = 1L, b = 2L)`;
- `{}` → `structure(list(), names = character())`, which re-encodes as `{}`;
- `{1: "ES256", 3: -7}` (a COSE header) → `cbor_map`;
- `{"": 1}` → `cbor_map`, because R reads an empty name as *no* name and would re-encode it as an array;
- a text-keyed map with a duplicate key, when `duplicate_keys = TRUE` → `cbor_map`, which keeps both entries in order.

```r
structure(
  list(keys = list(1L, 3L), values = list("ES256", -7L)),
  class = "cbor_map"
)
```

Two parallel lists, as `zuyaml_map` is, because iteration and encoding both want keys and values separately. Keys are decoded with the same mapping as values, so an integer key is an `integer`, a byte-string key a `raw`.

Under `"string"`, a text key names its entry as it is; a float key by its shortest round-trip decimal, always with a decimal point (`1.0`, `1.5`, `NaN`, `-Infinity`); and any other key by its RFC 8949 §8 diagnostic notation (`1`, `h'01'`, `true`, `[1, 2]`). Floats are formatted by zucbor because TinyCBOR's printer appends its width (`1.5f16`), which is encoding, not value. A collision after stringifying is `zucbor_duplicate_key` (status `ZU_ERR_KEY_COLLISION`) whatever `duplicate_keys` says, since a named list cannot record which entry was which.

The invariant, shared with `zuyaml`:

> A key R cannot hold as a name is preserved structurally, never coerced.

This matters more here than in YAML: COSE and CWT use small integer keys *as their normal case*, and a COSE header with both `1` and `"1"` as keys is well-formed and means two different things. `map_keys = "map"` exists for protocol code that wants one shape whatever a peer sent; `"string"` exists for exploratory reading and is refused (`zucbor_duplicate_key`) if stringifying makes two keys collide.

### 6.5 Duplicate keys

RFC 8949 §5.6 leaves a decoder's handling of duplicate keys to the application, and duplicate keys are a known way to make two parsers of the same COSE or WebAuthn structure see different values. So **they are rejected by default**, in the check phase, before any R object exists: `zucbor_duplicate_key`, carrying the offset of the second occurrence.

Detection is ours (§3). Keys are compared by **value**, not by encoded bytes, because `1` has more than one well-formed encoding (`0x01`, `0x1801`, …) unless the input is deterministic:

- integers by value, including across major type and width;
- text and byte strings by content, after joining chunks;
- floats by value after widening to double; `NaN` equals `NaN` for this purpose;
- simple values and booleans by value;
- arrays, maps and tagged keys by their encoded bytes. Two such keys equal in value but encoded differently are **not** detected. `deterministic = TRUE` closes the gap, since it rejects the non-shortest encoding first.

Each map's keys are sorted and adjacent keys compared: O(n log n) per map, with no hash table for an attacker to flood. The scratch space is `R_alloc`ed (§12).

`duplicate_keys = TRUE` accepts them; the map then decodes as a `cbor_map` (§6.4), never as a list with repeated names.

### 6.6 Tags

```r
tags = "convert"   # default: the tags below become R types, the rest cbor_tag
tags = "keep"      # every tag is a cbor_tag; nothing is converted or stripped
```

| tag | content | R, under `"convert"` |
|---|---|---|
| 0 | RFC 3339 date/time text | `POSIXct`, UTC |
| 1 | epoch seconds, integer or float | `POSIXct`, UTC |
| 2 / 3 | unsigned / negative bignum, byte string | the integer of that value, by §6.2 |
| 100 | days since 1970-01-01, integer (RFC 8943) | `Date` |
| 1004 | RFC 3339 full-date text (RFC 8943) | `Date` |
| 55799 | self-describe | stripped; the content decodes as if untagged |
| any other | any | `cbor_tag(tag, value)` |

```r
structure(list(tag = 24, value = as.raw(c(0x82, 0x01, 0x02))), class = "cbor_tag")
```

Decisions worth recording:

- **Tag 24 (embedded CBOR) is not decoded recursively.** The value stays a `raw`. An automatic nested decode would run outside the caller's limits, or inside them in a way that is hard to explain; `cbor_decode(tag$value)` is explicit and costs one line.
- **Invalid content for a converted tag is an error** (`zucbor_invalid_error`): a tag 0 string that is not RFC 3339, a tag 1 that is not a number. RFC 8949 §5.3.2 calls such an item invalid. The check refuses it whatever `tags` says, since validity is the check's business and `tags` only chooses the R type (corrected at Stage 10: this line used to say `"keep"` reads it anyway, which no stage implemented).
- **Bignum payloads over 128 bytes stay `cbor_tag`**, with the `raw` payload. Converting to decimal is quadratic in length; 128 bytes (a 1024-bit value) bounds that cost per item while covering every integer a protocol uses as a number. Nothing is lost: the payload is there.
- **Tag numbers above 2^53 are `zucbor_unrepresentable`.** A tag number is stored as a double. The IANA registry's largest assignments are far below this.
- A tag counts as one level of depth (§11), as it does in TinyCBOR's own validation.

UUIDs (37) and URIs (32) arrive as `cbor_tag`, and stay that way: Stage 10 settled §19 Q2 with handlers rather than built-in classes.

**Tag handlers** (Stage 10). `tag_handlers` is a list of functions named by tag number. When the build meets a tag with a handler, it builds the content with the call's options and passes it to the handler; the result takes the tag's place. Decisions:

- **A handler wins** over the conversions in the table, over 55799's stripping, and over `tags = "keep"`. A tag without one follows `tags`.
- **Handlers run in the build phase, after the check** (§4). User code never sees input that is malformed, invalid or over a limit, and never runs before the limits have passed. The check does not change: a handler gives meaning to valid content, it does not make other content valid, so a tag 0 with a number is still refused before any handler runs.
- **A result is kind "other"** (§6.3): an array holding one is a list, and a map whose key is one is a `cbor_map`.
- **Errors** in a handler become `zucbor_handler_error` with `tag` and `parent` (§10), raised from R (`zu_run_handler()`) by unwinding through the build, which is safe by §12. A warning passes through untouched.
- **Per call, no registry.** Node's cbor2 has a global `Tag.registerDecoder()`; here a result never depends on what some other package registered.
- **Nesting is explicit.** A handler that decodes tag 24's bytes calls `cbor_decode()` with limits of its own; the outer call's limits do not reach into it, which is the reason tag 24 is not decoded automatically.
- Handler names are whole numbers in canonical decimal up to 2^53, checked in R; C looks a tag up by binary search over the sorted numbers, and a tag above 2^53, which a double would round, never matches.
- The arguments are bound in a fresh environment whose parent is the namespace, so nothing is evaluated twice (the `do.call()` lesson of Stage 7) and a traceback shows names, not values. The encoder calls `as_cbor()` the same way (§7.5).

### 6.7 Dates and times

Tag 0 text is parsed by a project-owned RFC 3339 reader, not `strptime()`, so the result does not vary by platform or locale. Offsets are applied and the result is an instant in UTC, with fractional seconds kept. Calendar arithmetic uses Howard Hinnant's civil-date algorithm, as `zujson` does.

### 6.8 Valid CBOR R cannot hold

`zucbor_unrepresentable`, raised in the build phase, for:

- a text string containing U+0000 — no R string holds a NUL, and letting one reach `Rf_mkCharLenCE()` raises a bare `simpleError` that escapes the `zucbor_error` contract;
- a string longer than `INT_MAX` bytes;
- a tag number above 2^53;
- an integer beyond 2^53 with `big_integers = "error"`, including a 64-bit typed array element (§6.9);
- an array dimension above `INT_MAX` (§6.9).

These are the only cases where `cbor_validate()` says `TRUE` and `cbor_decode()` fails, which is rule 2 of §4. The NUL and length guards live in one function, `zu_mkchar()`, the only place a CHARSXP is made, so string values, names and keys cannot drift apart (the `zujson` invariant).

### 6.9 Typed and multi-dimensional arrays (RFC 8746)

Stage 12. Converted under `tags = "convert"`, like the tags of §6.6; a handler wins, and `tags = "keep"` keeps them.

| tag | content | R |
|---|---|---|
| 64, 68 (uint8, clamped), 72 (sint8) | bytes | `integer` |
| 65, 69 (uint16), 73, 77 (sint16) | bytes, big- or little-endian | `integer` |
| 74, 78 (sint32) | bytes | `integer`; `INT_MIN` is `NA_integer_` |
| 66, 70 (uint32), 67, 71 (uint64), 75, 79 (sint64) | bytes | `double` while every element is within 2^53, else by `big_integers` (the whole vector) |
| 80–82, 84–86 (binary16, 32, 64) | bytes | `double`, every bit kept |
| 83, 87 (binary128) | bytes | `cbor_tag`: no R type holds them |
| 76 | — | reserved by RFC 8746, so any other tag |
| 1040 | `[dimensions, elements]`, column-major | `matrix` or `array` |
| 40 | `[dimensions, elements]`, row-major | the same, reordered into R's column-major order |

Decisions:

- **Unsigned 32-bit is `double`**, by tag, not by value: a vector's type must not depend on whether one element passes `INT_MAX`.
- **The element size rule is the check's.** A typed array's content is a byte string (the tag-content table of §11) whose length is a whole number of elements (`ZU_ERR_TYPED_ARRAY`, `zucbor_invalid_error`, guard `typed-array-length`).
- **The shape rule is the check's.** The content of 40 or 1040 is exactly two items: a non-empty, untagged array of unsigned integers, then either an untagged array or one typed array (guard `array-parts`); and the product of the dimensions, saturating, is the number of elements (guard `array-shape`). Both are `ZU_ERR_ARRAY_SHAPE`. The walk tracks this in its frames (`nd_role`), so it costs nothing outside these tags.
- **A typed array is one item.** It is one CBOR data item, so `max_items` counts it once; what bounds the R allocation is `max_size`, at most 4 R bytes per input byte (uint8 to `integer`), the same bound as an array of small integers.
- **Byte by byte.** Elements are read and written a byte at a time in the declared order, so the platform's byte order never matters; floats are reassembled from bits with `memcpy()`.
- A typed array is kind "other" in the lattice of §6.3, and a one-element one is marked `I()`, so it re-encodes as a typed array (§7.6). A matrix's elements lose the `I()`: the `dim` attribute already says it is an array.
- Elements built by a tag handler that are not a vector of the right length leave the tag a `cbor_tag` holding `list(dimensions, elements)`; a handler's result is copied before `dim` is set on it, since it may be shared.

---

## 7. R to CBOR

### 7.1 Scalars and vectors

| R | CBOR |
|---|---|
| `NULL` | `null` |
| `NA` of any type | `null` |
| `TRUE` / `FALSE` | `true` / `false` |
| `integer` | integer |
| `double`, whole, within −2^64 … 2^64−1, not −0 | integer |
| any other `double`, incl. `NaN`, `±Inf`, `-0` | float, shortest exact width (§8) |
| `character` | text string, translated to UTF-8 |
| `raw` | **one** byte string, whatever its length |
| `factor` | its labels, as text |
| `POSIXct` | tag 1, integer if whole seconds, else float |
| `Date` | tag 1004, `"YYYY-MM-DD"`; tag 100 (days) for a year outside 0000–9999, which RFC 3339 cannot write; fractional days dropped, as `format.Date()` does |
| `cbor_bigint` | integer if within −2^64 … 2^64−1, else tag 2 / 3 |
| `cbor_tag` | tag, then its value |
| `cbor_map` | map with those keys |
| `cbor_simple` | that simple value |
| `list()` | `[]` |
| `structure(list(), names = character())` | `{}` |

Vectors follow `zujson`: a length-1 atomic vector is a scalar unless `I()`-wrapped or `auto_unbox = FALSE`; a longer one is an array; a matrix is a flat column-major array with `dim` dropped.

**Whole doubles become integers.** R has no integer literal, so a user writing a COSE header as `list(\`1\` = -7)` has written a double. As a float, `-7` would be a different CBOR value, and every COSE implementation would reject the algorithm identifier. The bound is the CBOR integer range, not 2^53: a double that is already whole *is* that integer. `-0` stays a float, since as an integer it would lose its sign. The consequence is that `1L` and `1` encode identically (§7.4).

**`NaN` is not `NA`.** CBOR has a NaN; JSON does not. `NA_real_` is a missing value and encodes as `null`; `NaN` encodes as the float NaN.

### 7.2 Lists and names

| R | CBOR |
|---|---|
| unnamed list or vector | array |
| fully, uniquely named list or vector | map with text keys |
| partially named | **`zucbor_invalid_argument`** |
| duplicate names | **`zucbor_duplicate_key`** |
| names containing `NA` or `""` | **`zucbor_invalid_argument`** |

`zujson` turns partial names into an array; `zuyaml` refuses them. This follows `zuyaml`: a deterministic encoder that silently drops data the caller attached produces bytes that are deterministic and wrong. Integer and other non-text keys are written with `cbor_map()`.

### 7.3 What cannot be encoded

`zucbor_unsupported_type`, for complex, closures, environments, external pointers, S4 objects, `POSIXlt` (a list of eleven fields, never what anyone meant by a timestamp), and data frames in v1. A `cbor_simple` in 20–31 (reserved, or spelled `false`/`true`/`null`/`undefined`) and an invalid `cbor_bigint` are `zucbor_invalid_argument`: the constructors validate, and the encoder validates again, because nothing stops a user building the structure by hand.

A vector whose class `zucbor` does not know is encoded as its underlying type (`zujson`'s rule): a new S3 class should not be a hard failure. Since Stage 10 it first goes through `as_cbor()` (§7.5), whose default returns it unchanged, so the rule still holds when no method exists.

### 7.4 Known lossy conversions

This table is part of the contract and goes into the user documentation as well.

| Construct | Behaviour | Round-trips? |
|---|---|---|
| `undefined` | decodes as `NULL` / `NA` | No — re-encodes as `null` |
| Float that is whole, e.g. `2.0` | decodes as `2`, re-encodes as integer `2` | No — float becomes integer |
| `1L` vs `1` | both encode as integer `1` | No — both decode as `1L` |
| Integer beyond 2^53 with `big_integers = "double"` | nearest double | No (opt-in) |
| Keys with `map_keys = "string"` | stringified | No (opt-in) |
| NaN payload and sign | canonical quiet NaN (`0xf97e00`) on encode | No |
| Indefinite lengths, non-shortest heads | decoded normally, re-encoded deterministically | Semantically |
| Map key order | re-encoded in deterministic order | Semantically |
| `list(1L)` | `[1]`, which decodes as `I(1L)` | Not as a list; CBOR → R → CBOR is exact |
| `list()` | `[]`, which decodes as `logical(0)` | Not as a list |
| `NA` | `null`, decodes as `NULL` or `NA` | Not as a typed `NA` |

What *does* round-trip is stated as a property and tested as one (§16): for any CBOR item `b` in deterministic form that decodes under the defaults, `cbor_encode(cbor_decode(b))` is `b`, except where one of the rows above applies. The one-element and boolean rules of §6.3 exist to make that true.

### 7.5 Classes of your own: `as_cbor()`

Stage 10. `as_cbor(x, ...)` is an exported S3 generic. The encoder calls it for an object none of whose classes it knows: anything but `POSIXct`, `Date`, `factor`, `data.frame`, `POSIXlt` and zucbor's four classes. `AsIs` neither counts as known nor asks for a call, so `I(x)` of a class with a method is converted. A method returns something the encoder knows, typically a `cbor_tag()`; with `tag_handlers` on the decoder it makes a class round-trip without zucbor knowing it.

- **Once per value.** The result is written as it is, even if its class is again unknown, though its elements are each converted in turn. So no chain of methods can loop, and nothing needs counting.
- **The default returns `x`**, and a result identical to `x` (the same object) is encoded as its underlying type: Stage 4's rule, unchanged. A different object *of the same class* is refused with `zucbor_unsupported_type`: it is most likely a method that forgot to convert.
- **Errors in a method propagate unchanged.** It is the caller's own code, called on the caller's own data, unlike a tag handler, which runs on untrusted input.
- **Determinism** is the method's to keep: the encoder cannot see what a method depends on. The documentation says a method should depend on nothing but `x`.
- **Map keys are encoded in one pass** (into a buffer owned like the output) so a method on a `cbor_map` key runs once; before Stage 10 a key was encoded twice, once to measure it.
- Calling R from the encoder longjmps through it on error; the output and key buffers are owned by finalized external pointers (§12), so nothing leaks.

### 7.6 Typed arrays on encode

Stage 12. `cbor_encode(..., typed_arrays = FALSE)`, off by default (roadmap principle 10, and many decoders do not read RFC 8746). With `TRUE`:

- an `integer` or `double` vector with no class but `AsIs`, written as an array rather than a single value, is tag 78 (sint32) or 86 (binary64), little-endian: every bit kept, `NA_integer_` as `INT_MIN` and `NA_real_` with its payload. A whole double stays a float, so §8's integer rule does not apply inside;
- a matrix or array of any type is tag 1040, `[dimensions, elements]` in R's own column-major order, the elements a typed array when numeric and a plain array otherwise;
- vectors with a class (factor, `POSIXct`, `Date`, `cbor_bigint`) keep their usual form.

The plan said "length two or more"; it became "written as an array", so that a decoded one-element typed array, marked `I()`, re-encodes as one. Measured on 10^6 elements (§17): a `double` vector is 8.0 MB against 8.9 MB, encodes in 33 ms against 70 and decodes in 27 ms against 214; an `integer` vector is 4.0 MB against 4.9 MB, 14 ms against 48 and 18 ms against 190.

---

## 8. Deterministic encoding

`cbor_encode()` always produces RFC 8949 §4.2.1 *core deterministic encoding*:

1. integers, lengths and tag numbers in the shortest head (TinyCBOR does this);
2. definite lengths only;
3. floats in the shortest of half, single and double that represents the value **exactly**; `NaN` as `0xf97e00`, `±Inf` as half;
4. map entries sorted by the **bytewise lexicographic order of their encoded keys**;
5. no duplicate keys.

The encoder is project code, `src/zu_encode.c` (§3 says why not TinyCBOR's). One routine runs twice over the R value:

~~Measure, then write into one exactly sized `RAWSXP`.~~ Since Stage 8 the encoder is one pass into a growing `malloc()` buffer owned by a finalized external pointer (§12), then one copy into a `RAWSXP` of exactly the right size, after which the buffer is freed eagerly: the measuring pass cost as much as the write for nothing a caller can see (§17). Each map's keys are encoded into `R_alloc` scratch, merge-sorted with `memcmp` (shorter-is-smaller on a common prefix, which is what TinyCBOR's own `CborValidateMapIsSorted` checks), and checked for duplicates, so a duplicate key fails before the output is allocated. Because the encoding is deterministic, two keys are equal in value exactly when their bytes are equal: `1L` and `1` are one key. Keys from R names are always text strings, whatever `auto_unbox` says. So `cbor_validate(cbor_encode(x), deterministic = TRUE)` is `TRUE` for every `x` that encodes — a property test (§16).

Float width selection is project code (`zu_float.c`), not TinyCBOR's internal `encode_half()`, which is private to its translation units and selects compiler intrinsics by platform. It is tested exhaustively: all 65,536 half-precision bit patterns must survive double → half, and every width decision is checked against the round-trip `(double)(narrow)x == x`.

Typed arrays (§7.6) are deterministic too: little-endian on every platform, written a byte at a time. They are not part of RFC 8949's deterministic encoding, which says nothing about them, and are off by default.

The bytewise order is RFC 8949's. It is **not** the length-first order of RFC 7049 §3.9, which CTAP2 calls "canonical" (§19).

---

## 9. Input sources

`cbor_decode()` needs the whole item before it can check it (§4), so decoding is always of a complete buffer. There is no incremental decoder, and there will not be one: an incremental decoder has to build R objects before it has seen the end of the input, which is what the check phase exists to prevent.

`cbor_read()` takes a path, a URL or a connection, and reads **at most `max_size + 1` bytes** with `readBin()` in 64 KiB blocks, so an oversized or endless source fails with `zucbor_size_limit` having read one byte past the limit, not after exhausting memory. The path/URL/connection resolution is `zuxml`'s `R/zu_source.R` (`zu_open_input()`), copied verbatim with its origin line, following its conventions: an unopened connection is opened `"rb"` and closed on exit; an open one must already be binary and is left open.

The read loop is in R, not C. `zuxml`'s C connection reader uses `R_GetConnection()` / `R_ReadConnection()`, which are experimental API and cost a NOTE on R 4.5's check. Whole-buffer decoding gains nothing from reading in C, so `zucbor` does not copy `src/zu_source.h`.

---

## 10. Errors

Every failure raises a condition whose class vector ends `c("zucbor_error", "error", "condition")`, built in C where the cause is known (`zu_stop()` in `src/zu_cond.c`, as in `zujson`). R-side argument checks raise the same shape.

```text
zucbor_error
├── zucbor_invalid_argument   an unusable argument
├── zucbor_parse_error        not well-formed: truncated, reserved additional info,
│                             unexpected break, trailing bytes, empty input
├── zucbor_invalid_error      well-formed but invalid: bad UTF-8, wrong tag content
├── zucbor_deterministic_error  not deterministic, with deterministic = TRUE
├── zucbor_duplicate_key
├── zucbor_limit_error
│   ├── zucbor_depth_limit
│   ├── zucbor_size_limit
│   └── zucbor_item_limit
├── zucbor_unrepresentable    valid CBOR R cannot hold (§6.8)
├── zucbor_unsupported_type   an R value with no CBOR form (§7.3)
├── zucbor_handler_error      a tag handler raised an error (§6.6): tag, parent
└── zucbor_io_error           a file or connection could not be read
```

Every decode-side condition carries:

- `offset` — the 0-based byte offset of the item at fault, or `NA` when only `cbor_value_validate()` saw the fault (it reports no position; §3). Since Stage 8 that is only the deterministic-encoding checks: UTF-8 moved into the walk (one pass instead of two) and, with tag content, has an offset;
- `status` — the TinyCBOR enumerator's **name** (`"CborErrorUnexpectedEOF"`), or zucbor's own (`"ZU_ERR_DUPLICATE_KEY"`);
- for a limit error, `limit` (the argument's name) and `limit_value`;
- for `zucbor_invalid_argument`, `arg`.

R maps a status to a class by the enumerator's name, which C returns beside the message, never by matching English (the `zuxml` #40 rule). A `CborError` the map does not know is a bare `zucbor_error`, and a test enumerates every `CborError` in the vendored `cbor.h` so that a new upstream code fails the suite rather than falling through quietly.

Users see:

```text
CBOR parse error at byte 41: unexpected end of data
```

Tests assert on condition classes and fields, never on message text.

---

## 11. Limits and hostile input

Threat model: **the input is hostile**, and so is anything a peer can influence about its size.

| Limit | Default | Enforced |
|---|---|---|
| `max_size` | 64 MiB | before the check phase; while reading in `cbor_read()` |
| `max_depth` | 256, at most 1023 | check phase, at each container or tag entry |
| `max_items` | 1e6 | check phase, per data item, including every string chunk |

**Depth counts containers and tags, not values.** The root array is level 1; a scalar inside it is no level of its own; a tag is one level. The encoder charges depth identically, so `cbor_encode()` cannot emit what `cbor_decode()` at the same `max_depth` refuses — output the package will not read back is the worst bug shape available (`zujson` §9).

**Why 1023 is a hard ceiling.** `cbor_value_validate()` recurses, capped by `CBOR_PARSER_MAX_RECURSIONS` (1024), and the build phase recurses too. The validator charges each container or tag a level *before* testing for zero, so the deepest item it accepts is 1023 levels, for arrays and tags alike (measured at Stage 1). Raising the cap is a C-stack decision, not a user preference. `max_depth` above 1023 is `zucbor_invalid_argument`. `ZU_MAX_DEPTH_CAP` is defined as 1023, and `src/zu_tinycbor_check.c` fails the build if it stops being `CBOR_PARSER_MAX_RECURSIONS - 1`.

**Why `max_items` exists when `max_size` bounds the input.** Each item costs one input byte but up to ~56 bytes of R heap as a list element, so 64 MiB of `0x80` (empty arrays) in one array would ask R for several gigabytes. 1e6 items bounds the worst case near 100 MB of R objects. Telemetry batches larger than that raise the limit deliberately.

**Length headers are never trusted for allocation** (§4, rule 1). The build phase allocates from counts the check phase observed.

A limit is a positive whole number, or `Inf` for `max_size` and `max_items` (the largest value the C type holds). `0`, negatives, fractions, `NA`, strings, vectors, and finite values past the C type are `zucbor_invalid_argument` — a security limit silently replaced by a default is a limit the caller did not set (`zuxml` #40).

**Interrupts.** The check and build phases call `R_CheckUserInterrupt()` every 65,536 items. That is safe because nothing they hold needs freeing (§12).

**`deterministic = TRUE`** adds `CborValidateCanonicalFormat` to the validation flags and makes the walk reject a bignum whose value fits a plain integer (RFC 8949 §3.4.3). It is for inputs that are about to be hashed or signed again, where a second encoding of the same value is an attack surface.

`cbor_value_validate()` runs only for `deterministic = TRUE`, with `CborValidateCanonicalFormat` (`ZU_VALIDATE_FLAGS`); every other check is the walk's, shared by every read path, so `cbor_decode()` and `cbor_validate()` cannot disagree about the bytes (the `ZUJSON_READ_FLAGS` rule). Three checks TinyCBOR offers are the walk's instead:

- **UTF-8**, not `CborValidateUtf8`: each chunk validated as the walk meets it (RFC 8949 §3.2.3), in the same pass, with an offset (Stage 8).

- **Trailing bytes**, not `CborValidateCompleteData`: a sequence validates item by item, where the next item's bytes are not garbage, and one check in one place serves both.
- **Tag content**, not `CborValidateTagUse` (§3): each tag's content type is checked as the walk meets it, against TinyCBOR's table with its two errors corrected, plus the tags zucbor converts. A restricted tag wrapping another tag is refused, since a tag is not any of the types it allows.

| tag | content required |
|---|---|
| 0, 32–36, 1004 | text string |
| 1 | integer or float |
| 2, 3, 24 | byte string |
| 4, 5, 16–18, 96–98 | array |
| 100 | integer |
| any other, including 21–23 and 55799 | anything |

Status `CborErrorInappropriateTagForType`, class `zucbor_invalid_error`, with the tag's offset.

---

## 12. Memory model

The invariant, inherited from `zukomp` and `zujson`:

> Anything holding heap state across a longjmp must be owned by R.

`zucbor` meets it more simply than its siblings, because TinyCBOR allocates nothing on the paths used here:

- the parser and validator read the caller's buffer (the `RAWSXP` itself, never a copy);
- the encoder writes into a `malloc()` buffer owned by a finalized external pointer, copied once into the result and then freed eagerly (Stage 8); since Stage 10 each non-text map key is encoded the same way;
- all scratch — the walk's container stack, duplicate-key descriptors, encoded map keys during sorting — is `R_alloc`ed, which R releases when the `.Call` returns *or* unwinds.

So no C function in the package has an error cleanup path, and `zu_stop()`, `R_CheckUserInterrupt()` and any R allocator may jump from anywhere. Since Stage 10 so may user code: tag handlers run in the middle of the build and `as_cbor()` methods in the middle of the encoder, and either may error, warn, be interrupted, or call zucbor again. Nothing in the build or the encoder is static, so a nested call shares no state with the one it runs inside.

`vmaxset()` releases scratch in bulk, and anything allocated after the mark goes with it. The encoder's per-depth map entry pools (Stage 8) were allocated inside a parent map's mark and outlived it until Stage 10, which found the reuse by reading the code: a map's end now forgets every deeper pool. `cborparser_dup_string.c`, the only TinyCBOR file that calls `malloc`, is not vendored (§13), so the rule cannot be broken by accident.

PROTECT discipline is checked by `rchk` and `gctorture` in CI, and by hand with `gctorture(TRUE)` before a C change is called done.

---

## 13. TinyCBOR vendoring and build

### Version

Pinned at **TinyCBOR 7.0** (tag `v7.0`, commit `6442e749ca811e24afad1551338a45c75e09808f`, released 2026-02-18), which is also the floor. 7.0 is the first release that compiles in C23 mode (upstream #309), and R ≥ 4.5 compiles packages as C23 where the compiler supports it; 0.6.1 does not build there. Re-verify the current release at every re-vendoring, and check the upstream security advisories. Never track `main`. Of the changes on `main` since 7.0 (to 2026-09-23), the library ones touch `cbortojson.c`, which is not vendored, and `compilersupport_p.h`, which is: the GCC < 11 build fix of trap 8 below.

`src/vendor/PROVENANCE`, one level above the vendored tree so the tree stays byte-identical: upstream URL, tag, commit, tarball SHA-256 (trust on first use), import date, licence, the file list, local patches (none), and the compile configuration.

### Files

Vendored into `src/vendor/tinycbor/`, byte-identical, listed in `tools/tinycbor-files.txt`:

`cbor.h`, `cborerrorstrings.c`, `cborparser.c`, `cborvalidation.c`, `cborinternal_p.h`, `cborinternalmacros_p.h`, `compilersupport_p.h`, `utf8_p.h`, `memory.h`, and `LICENSE`.

Not vendored: `cborencoder.c` (zucbor encodes itself, §8; dropped at Stage 4), `cborpretty.c` (zucbor prints diagnostic notation itself, §5; dropped at Stage 5), `cbortojson.c` and `cborjson.h` (JSON is `zujson`'s job), `cborpretty_stdio.c` (`FILE *`), `open_memstream.c`, `cborparser_dup_string.c` (`malloc`, §12), `cborencoder_close_container_checked.c` (a deprecated alias), the two `*_float.c` helpers (half-float conversion is ours, §8), the `.in` templates, `parsetags.pl`, `tags.txt`, CMake, tests, examples and tools.

### Configuration

TinyCBOR 7.0 generates two headers at CMake time. They are **project-owned**, outside the vendor tree, in `src/tinycbor/`, and `PKG_CPPFLAGS` puts that directory on the include path:

- `tinycbor-export.h` — `#define CBOR_API` (empty; static linkage into our shared object);
- `tinycbor-version.h` — `TINYCBOR_VERSION_MAJOR 7`, `MINOR 0`, `PATCH 0`, written by `tools/update-tinycbor` from the tag.

`CBOR_EXTERNAL_CFG` is not defined; `CBOR_PARSER_MAX_RECURSIONS` stays at its default of 1024, admitting 1023 levels (§11). `cbor_malloc` is irrelevant, since nothing that calls it is compiled.

### The traps

Named here so CI does not have to discover them:

1. **Generated headers.** Never copy a CMake-generated `tinycbor-version.h` from a build directory; `tools/update-tinycbor` writes it from the tag, and `tools/verify-vendor` checks it agrees with `PROVENANCE`.
2. **C23.** Build with R's default standard on R-devel and R-release, and with `-std=gnu99` on oldrel; a TinyCBOR that compiles in only one mode fails somewhere on CRAN.
3. **`cbor_assert()` under `NDEBUG`.** R compiles with `-DNDEBUG`, and TinyCBOR 7.0 then defines `cbor_assert(cond)` as `if (!(cond)) unreachable()`. A violated TinyCBOR precondition — calling `cbor_value_get_int64()` on a string, say — is **undefined behaviour, not an abort**. Every TinyCBOR accessor is called only after checking the item's type; the sanitizer jobs build with `-UNDEBUG`, so a violation there aborts visibly instead.
4. **stdio and abort symbols.** `R CMD check` NOTEs a shared object that references `stdout`, `stderr`, `printf`, `abort` or `exit`. None of the vendored files uses stdio; `cborpretty_stdio.c` and `cbortojson.c`, which do, are not vendored. `tools/check-symbols` runs `nm -u` over the built object and fails on any of them, and has been seen to fail on a planted `fprintf(stderr, …)`.
5. **MinGW formats.** The float formatter uses `"%.*e"` and reads the digits back with `strtod()`. On Windows it must get C99 behaviour, not MSVCRT's, so `-D__USE_MINGW_ANSI_STDIO=1` sits in the one `src/Makevars`, where it is inert off Windows. (It was first there for `cborpretty.c`'s `PRIu64` formats, which left with that file at Stage 5.) No project code uses `<inttypes.h>` format macros: 64-bit integers are formatted by hand (`zu_u64_to_dec()`).
6. **Half-float intrinsics.** `cborinternal_p.h` selects F16C / SSE2 intrinsics or `_Float16` by compiler and target. We do not call its half-float helpers, but the header is compiled everywhere; i386-without-SSE2 was fixed only in 7.0 (upstream #302). Where `_Float16` is used, the compiler emits calls to its runtime's conversion helpers (`__extendhfsf2`, `__truncsfhf2`; seen with Apple Clang 17 at Stage 1), so the shared object depends on the platform's compiler runtime providing them. CI's full matrix is what proves it does.
7. **Portable make.** `src/Makevars` lists every object in `OBJECTS` by hand; no `$(wildcard)`, no `$(shell)`, no `-Wno-*`. There is no `Makevars.win`: R on Windows falls back to `Makevars`, and one file cannot drift from itself. `.Rbuildignore` keeps `src/**/*.o`, `*.so` and `*.dll` out of the tarball.
8. **GCC < 11.** 7.0's `compilersupport_p.h` defines `CBOR_FALLTHROUGH` as `[[fallthrough]]` whenever `__has_cpp_attribute(fallthrough)` is true, and GCC before 11 says it is in C mode too but rejects the syntax: a hard compile error. Upstream fixed it on `main` after 7.0 (`__has_c_attribute` for C), unreleased as of 2026-09-30. **No CRAN flavour is affected**: on 2026-09-30 the oldest GCC in CRAN's check flavours is 14.3 (Windows), and clang reports `__has_cpp_attribute(fallthrough)` false in C mode, falling back to `__attribute__((fallthrough))` (checked with Apple Clang 17 under gnu99, gnu17 and gnu2x, where the vendored subset compiles clean with `-Wall`; Apple Clang 14 on `r-oldrel-macos-arm64` is confirmed by Stage 1's CI). Who is affected is a user building from source with an old system GCC: RHEL/Rocky/Alma 8 without a gcc-toolset (GCC 8), Ubuntu 20.04 (GCC 9), Debian 11 (GCC 10). §19, Q7.

### Updating

`tools/update-tinycbor <tag>` fetches the release tarball, records its SHA-256, replaces `src/vendor/tinycbor/` with the listed files, rewrites the two generated headers and `PROVENANCE`, and prints the next steps: `tools/verify-vendor`, `R CMD check`, the conformance and fuzz runs. `tools/verify-vendor` re-derives the tree and fails on any difference. A CBOR parser gets security releases; this has to be a ten-minute job.

---

## 14. Portability and CRAN

- Project code is portable C99, compiling warning-free under `-Wall -Wextra -Wpedantic`; warnings there are CI failures. Vendored TinyCBOR is not held to that.
- `src/init.c` registers every entry point; `R_useDynamicSymbols(dll, FALSE)`.
- Licence MIT, matching TinyCBOR and the family. `Authors@R` lists the copyright holders of vendored code as `cph`, with a comment naming TinyCBOR. That is **Intel Corporation** alone: upstream also carries a 2019 S. Phirsov notice, but only in files outside the vendored subset, so that holder is not ours to declare. Re-check at every re-vendoring (`grep Copyright src/vendor/tinycbor/*`). `inst/COPYRIGHTS` records zucbor's and TinyCBOR's notices separately; `LICENSE.note` records provenance.
- `Language: en-GB`; domain terms in `inst/WORDLIST` via `spelling::update_wordlist()`.
- `.Rbuildignore` covers `.agents/`, `tools/`, `.claude/` and design notes. The agent instructions live in `.claude/CLAUDE.md`, not at the root: pkgdown publishes every root-level Markdown file as a page, and has no setting to exclude one.
- `NEWS.md` carries `# zucbor <version>` before the first check that must be clean.

---

## 15. Layout and naming

```text
R/{decode,encode,read,validate,diagnose,classes,info,conditions,args,zu_source,zucbor-package}.R
src/init.c
src/zucbor.h                  internal prototypes
src/zu_cond.c                 conditions, status names
src/zu_check.h                the check phase's interface, R-free (builds with -DZU_STANDALONE)
src/zu_walk.c                 check phase: walk, limits, duplicate keys, tag content; R-free
src/zu_status.c               CborError and zucbor status names; R-free
src/zu_validate.c             cbor_validate()'s .Call entry point
src/zu_build.c                build phase: §6
src/zu_cbor.h                 internal prototypes that take TinyCBOR types
src/zu_encode.c               §7, §8
src/zu_float.c                width selection, half conversion
src/zu_bigint.c               decimal <-> magnitude
src/zu_time.c                 RFC 3339, civil dates
src/zu_diag.c                 diagnostic notation, and the float formatter it and map keys share
src/zu_config.h               constants shared with TinyCBOR-facing code; no R headers
src/zu_tinycbor_check.c       build fails if ZU_MAX_DEPTH_CAP != CBOR_PARSER_MAX_RECURSIONS
src/zu_info.c                 zucbor_info(): version, cap, self-test
src/tinycbor/                 project-owned generated headers (§13)
src/vendor/tinycbor/          verbatim subset
src/vendor/PROVENANCE
tools/update-tinycbor, tools/verify-vendor, tools/tinycbor-files.txt, tools/check-symbols,
tools/check-status-table       zu_cond.c's CborError table == the vendored cbor.h's enum
tools/sanitizer-exercise.R    base-R driver for the ASan containers
tools/run-fuzz, tools/fuzz-seeds.R, tools/run-mutation-check, tools/run-lint, tools/check-no-network
fuzz/                         libFuzzer targets, canary, arena, probe (not in the tarball)
```

| layer | prefix |
|---|---|
| R exports | `cbor_` (plus `zucbor_info()`) |
| R internals | `zu_` |
| C internals | `zu_` |
| `.Call` entry points | `zucbor_` |
| condition classes | `zucbor_` |
| S3 classes returned to users | `cbor_` |

The value classes are `cbor_*`, not `zucbor_*`, because users construct them (`cbor_map()`, `cbor_tag()`) and they name CBOR concepts, not package internals. `zuyaml`'s `zuyaml_map` / `zuyaml_bigint` are classes users only receive.

---

## 16. Testing

### Conventions

The family's: self-sufficient `test_that()` blocks, classes not messages, green under `shuffle = TRUE`, serial (no `Config/testthat/parallel`, so gctorture and valgrind see the C code), a suite of a few seconds. `expect_cbor(x, "hex")` asserts exact output bytes; `expect_roundtrip()` uses `identical()`.

### Mapping

Every row of the §6 and §7 tables has a test. The tables in the roxygen docs, this document and the tests are the same table three times; changing one means changing all three.

### Conformance

- **RFC 8949 Appendix A**, every example, both directions: decode the hex and compare with the expected R value; encode the value and, where the example is in deterministic form, compare bytes.
- **RFC 8949 Appendix F**, every not-well-formed example must be `zucbor_parse_error`.
- `cbor/test-vectors` (`appendix_a.json`) at a pinned commit, through `tools/run-conformance`, outside the suite, with every difference attributed to a named cause by rule and each cause held to a baseline count.
- QCBOR's `not_well_formed_cbor.h`, all 122 vectors, as must-reject cases: a superset of Appendix F from the author who contributed most of it.
- Real structures, as local fixtures regenerated from pinned sources by `tools/update-fixtures` (`tests/testthat/fixtures/README.md` lists sources and licences): all 306 `cose-wg/Examples` messages and their 345 `ToBeSign` / `ToMac` / `AAD` structures, the RFC 8392 CWT examples, the 15 WebAuthn Level 3 attestation objects, and the RFC 8428 SenML pack. The structures a signature or MAC covers must re-encode to exactly the signed bytes.
- `tools/run-conformance` fails if any committed fixture differs from a fresh regeneration from its source.

### Properties

- `cbor_encode(x)` is identical across repeated calls, across sessions, and on every CI platform (a checked-in hex fixture).
- `cbor_validate(cbor_encode(x), deterministic = TRUE)` for every encodable `x`.
- `cbor_decode(cbor_encode(x))` recovers `x` modulo §7.4.
- `cbor_encode(cbor_decode(b))` is `b` for deterministic `b`, modulo §7.4.
- All 65,536 half-precision patterns round-trip through `zu_float.c`.

### Security (permanent regressions)

- A 9-byte array header claiming 2^64 − 1 elements → `zucbor_parse_error`, with R's heap unchanged before and after.
- 100,000 nested arrays, and 100,000 nested tags → `zucbor_depth_limit`, no stack overflow.
- `max_items` + 1 empty arrays → `zucbor_item_limit` before any R allocation.
- Duplicate keys in every comparison class of §6.5, including `1` vs `0x1801`.
- A NUL in a text string or a map key → `zucbor_unrepresentable`, while `cbor_validate()` accepts the same bytes. In a tag 0 string it is `zucbor_invalid_error`: that text never becomes an R string, it is simply not a date.
- Invalid UTF-8 in text and in keys; truncation at every byte of every Appendix A example.
- `cbor_read()` on an endless connection stops one byte past `max_size`.
- Interrupt: `setTimeLimit()` inside the same expression as a large decode unwinds cleanly and the same input then decodes (`zuxml` #37).
- `tools/run-mutation-check` removes each guard in turn (depth, items, size, duplicate keys, NUL, length headers) and requires its hostile input to stop being refused. A guard whose removal changes nothing was never doing anything.
- No test performs network I/O; asserted by a grep in CI.

### Fuzzing and native checks

The check phase builds without R: `src/zu_check.h` declares it with no SEXP, and scratch memory, interrupt checks and "no offset" are three hooks (`zu_scratch()`, `zu_interrupt_check()`, `ZU_NO_OFFSET`). They are `R_alloc()`, `R_CheckUserInterrupt()` and `NA_REAL` in the package, and an arena, a no-op and `NAN` under `-DZU_STANDALONE`. That lets libFuzzer run `fuzz/fuzz_check.c` over the same `zu_walk.c` the package uses. The first input byte picks the options, and besides sanitizer findings the target traps on a broken monotonicity invariant: relaxing an option (deterministic, duplicate keys, depth, items, sequence) can only accept more. `fuzz/fuzz_canary.c` links the same code and must crash before any real target is trusted. Seeds are built from the embedded vectors and the conformance fixtures, the grown corpus is cached between CI runs, and runs last 2 minutes per pull request and 30 minutes nightly.

The build, encode and diagnostic phases build R objects, so they are not libFuzzer targets. They are fuzzed through R instead: `tools/sanitizer-exercise.R` drives every phase over the vectors, truncations and random mutations in the ASan containers, and the property tests (§16, *Properties*) run under UBSan with `-UNDEBUG` (§13, trap 3). Valgrind, `rchk`, gctorture and LTO run through `pedrobtz/r-actions`' `native-checks.yaml`, as in `zujson`.

`tools/run-mutation-check` disables each guard in the check phase, marked `/* GUARD: name */`, in a scratch copy, and requires its hostile input to get a different answer through `fuzz/probe.c`. Removing the container-depth guard does not merely change the answer, it overruns the walk's container stack, which is sized from `max_depth`, so that guard is also a memory-safety guard. `tools/run-lint` holds project C, R-free build included, to `-Wall -Wextra -Wpedantic -Wshadow -Werror`, after first seeing a planted warning fail. `tools/check-no-network` asserts that no test opens a URL or a socket.

---

## 17. Performance targets

The design set these before any code existed:

| | Target |
|---|---|
| Decode | faster than `zujson::json_parse()` on the same data as JSON |
| Encode | faster than `zujson::json_write_raw()` on the same data |
| Check phase | ≤ 30 % of total decode time |
| R allocations | none in the check phase; the encoder allocates its output once |
| Install time | seconds, from source, everywhere |

Measured at Stage 8 (`tools/run-benchmarks`, local macOS, R 4.5.2; ratios are CBOR time over JSON time, so below 1 is faster):

| Fixture | decode | encode | check share |
|---|---|---|---|
| 1 KiB message | 3.9× | 2.4× | 0.62 |
| 100 KiB telemetry | 2.2× | 1.3× | 0.41 |
| 10 MiB document | 2.0× | 1.1× | 0.40 |
| many tiny items | 1.7× | 0.95× | 0.43 |
| large strings | 0.95× | 0.95× | 0.26 |

Encoding meets its target within a few tens of percent; decoding does not, and the check-phase share is above its target. The reasons are measured, not guessed:

- **The check phase is the design.** Checking the whole input before building anything (§4) means two passes, and the first costs about 40 % of a decode. zujson's yyjson is itself among the fastest parsers there is. "Faster than zujson" was aspirational from the start; the property the check buys is worth more to this package's users than the difference.
- **Stage 8 removed what was not the design:** a second validation pass for UTF-8 (now in the walk, which also gave UTF-8 faults offsets), an allocation per map for duplicate-key sorting, a copy of every text string, a throwaway vector per map key, an R object per scalar array element (now staged in C and allocated only if the array does not simplify), a measuring pass in the encoder (now one pass into a growing buffer owned by a finalized external pointer, §12), and per-map key encoding when the keys are R names (text keys sort by length then bytes, which is their encodings' bytewise order). Together they took decoding from 3.4–4.5× to 1.7–2.2× and encoding from 1.7–3.3× to 0.95–1.3×.
- **The 1 KiB row is fixed cost:** about 20 µs of R-level argument checking per call, against a 7 µs JSON parse.

Revised targets, which the numbers above meet and which a regression would miss: decode within 2.5× of zujson on the same data, encode within 1.5×, check phase at most half of decode time. Benchmarks are not in CI; shared runners are too noisy to gate on.

**Typed arrays** (Stage 12, §7.6), 10^6 elements, median of ten on the same machine as the rows above:

| | plain array | typed array (`typed_arrays = TRUE`) |
|---|---|---|
| `double`: size | 8.92 MB | 8.00 MB |
| `double`: encode / decode | 70 ms / 214 ms | 33 ms / 27 ms |
| `integer`: size | 4.87 MB | 4.00 MB |
| `integer`: encode / decode | 48 ms / 190 ms | 14 ms / 18 ms |

The decode gain is the check phase's and the build's per-item work disappearing: a typed array is one item.

---

## 18. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | CBOR library | TinyCBOR, vendored |
| 2 | TinyCBOR release | Pinned 7.0; floor 7.0 (C23) |
| 3 | Check before build | Yes, whole item, always; `cbor_validate()` is the check phase |
| 4 | Verbs | `decode` / `encode` |
| 5 | Input to `cbor_decode()` | raw only; files and connections via `cbor_read()` |
| 6 | Sequences | yes, `*_seq()` functions |
| 7 | Integers beyond 2^53 | `cbor_bigint` by default (`zuyaml`), `"double"` opt-in |
| 8 | Array simplification | `zujson`'s preserve lattice, extended (§6.3) |
| 9 | Non-text keys | `cbor_map`; named list only when faithful |
| 10 | Duplicate keys | Rejected by default, compared by value |
| 11 | Tags converted | 0, 1, 2, 3, 100, 1004, 55799 |
| 12 | Tag 24 | not decoded recursively |
| 13 | `undefined` | decodes as `null` |
| 14 | Encoding determinism | always RFC 8949 §4.2.1, bytewise key order |
| 15 | Whole doubles | encoded as integers |
| 16 | Partial names on encode | error (`zuyaml`), not array (`zujson`) |
| 17 | `Date` on encode | tag 1004 |
| 18 | `POSIXct` on encode | tag 1 |
| 19 | Limit defaults | §11 table; `max_depth` ≤ 1023 |
| 20 | Streaming decode | never; whole-buffer only |
| 21 | Scratch memory | `R_alloc` only; TinyCBOR allocates nothing |
| 22 | C API | none in v1 |
| 24 | Encoder | Project code, not TinyCBOR's (§3, §8) |
| 27 | Diagnostic printer | Project code, not TinyCBOR's; matches RFC 8949 Appendix A (§5) |
| 25 | Booleans in arrays | A kind of their own; `[true, 1]` is a list (§6.3) |
| 26 | One-element arrays | Marked `I()` on decode, so they re-encode as arrays (§6.3) |
| 23 | GCC < 11 (trap 8) | Ship 7.0; the README states GCC ≥ 11 (Stage 8). Revisit when upstream releases the fix |
| 28 | Tags zucbor does not convert | Per-call `tag_handlers`, run after the check; no global registry (§6.6, Stage 10) |
| 29 | Classes zucbor does not know | Exported S3 generic `as_cbor()`, called once per value (§7.5, Stage 10) |
| 30 | UUID, IP address, decimal fraction | Recipes in the examples article, not built-in classes (Stage 10) |
| 31 | CBOR inside binary framing | `cbor_decode_prefix()`: first item checked and decoded, the rest not read (§5, Stage 11) |
| 32 | RFC 8746 typed arrays | Decoded always (§6.9); encoded only with `typed_arrays = TRUE`, as tags 78, 86 and 1040, little-endian (§7.6, Stage 12) |

---

## 19. Open questions

1. **CTAP2 canonical order.** CTAP2 requires RFC 7049 length-first key order; RFC 8949 deterministic encoding is bytewise. They differ (e.g. `24` versus `-1`). Decoding CTAP2 data needs nothing, since signatures cover bytes, not re-encodings. An authenticator emulator would need a `key_order` argument. Add it when a caller asks. Deferred again in [roadmap.md](roadmap.md) (Stages 10–16).
2. ~~**UUID and URI tags.**~~ Closed at Stage 10: neither becomes a class. `tag_handlers` and `as_cbor()` let a caller convert any tag, and the examples article carries recipes for UUIDs, IP addresses and decimal fractions. Decision 30.
3. **Data frames.** Encode row-oriented as `zujson` does, and decode arrays of text-keyed maps opt-in. Deferred to keep v1's mapping small; SenML users are the likely askers. Planned as Stage 14 of [roadmap.md](roadmap.md), inside v1.
4. ~~**Validation offsets.**~~ Closed at Stage 8: UTF-8 and tag content are checked by the walk and have offsets; only deterministic-encoding faults, from TinyCBOR's validator, have `offset = NA`. Validating per item from the walk would recover it at some cost to throughput. Measure first.
5. **The bignum conversion cap** (128 bytes, §6.6). Revisit if a protocol uses larger integers as numbers rather than as opaque bytes.
6. **A C API for siblings.** `zucrypt` (COSE signing) or `zuhttp` (`application/cbor`) may want CBOR from C. Design it only once one of them has a concrete need, following `zukomp`'s registered-table pattern (`zujson` §15).
7. ~~**GCC < 11**~~ Closed at Stage 1 (2026-09-30): 7.0 is still upstream's newest release, so it ships, and the README states the GCC ≥ 11 requirement. Decision 23.

---

## 20. Acceptance criteria for v1

1. Builds from source on Windows, macOS and Linux, R release, devel and oldrel, with no system library, CMake or autotools.
2. No R object is allocated before the check phase has passed; verified by the 2^64-length and `max_items` fixtures.
3. Every oversized, deep, truncated or malformed input fails through a classed `zucbor_error` carrying its status; none crashes, hangs, or reaches R's allocator unbounded.
4. Duplicate keys are rejected by value by default.
5. Encoding is deterministic: byte-identical across calls, sessions and platforms, and `cbor_validate(…, deterministic = TRUE)` accepts every output.
6. RFC 8949 Appendix A passes in both directions; every Appendix F example is rejected.
7. Every documented mapping row has a test, and the three copies of each table agree.
8. Round-trip properties of §16 hold across the corpus.
9. Fuzzing under ASan + UBSan finds nothing in project-owned code over a sustained run; the gate has been seen to fail on its canary.
10. Vendored TinyCBOR provenance is recorded and `tools/verify-vendor` reproduces the tree.
11. `R CMD check --as-cran` is clean on all three platforms, with no stdio or abort symbols in the shared object.
12. The COSE, CWT and WebAuthn fixtures decode to the values their specifications state.
