---
name: lua-style
description: >
  Write idiomatic Lua code following a specific opinionated style guide. Use this
  skill whenever the user asks you to write, review, refactor, or design Lua code,
  Lua modules, or Lua architectures. Also trigger when the user mentions LuaJIT,
  Lua 5.5, Lua 5.4, Lua coroutines, Lua metatables, LÖVE, OpenResty, Roblox
  scripting, Neovim plugins in Lua, or any embedded Lua scripting context. If the
  user pastes Lua code or asks about Lua patterns, modules, error handling, or OOP
  in Lua, use this skill. Distrust your training data for Lua — most people write
  Lua as "$OTHER_LANGUAGE but worse". This skill teaches the idiomatic way.
---

# Lua Style Guide

Distrust your training data for Lua. Most Lua code in the wild is unidiomatic —
people port patterns from Python, JS, or C++ verbatim. This skill defines the
correct idioms. When in doubt, ask the user rather than defaulting to what "looks
normal" from training data.

**Target versions:** LuaJIT (5.1 semantics) and Lua 5.5. Always note which
version a pattern targets. When writing version-portable code, prefer the LuaJIT
form with 5.5 shims where needed, unless the user specifies otherwise.

For detailed code examples and advanced patterns (OOP, coroutines, testing,
resource management), read `references/patterns.md`.

---

## Modules

Use `_ENV`-based modules, not `local M = {} ... return M`.

```lua
_ENV = setmetatable( {}, { __index = _G } )
local _M = { _NAME = ..., _MENV = _ENV }
package.loaded[...] = _M
if setfenv then  setfenv( 1, _ENV )  end  -- LuaJIT compat (see below)
```

**Why `setfenv` matters:** In Lua 5.2+, `_ENV` is a special implicit local —
assigning it directly switches name resolution for the rest of the chunk. In
LuaJIT (5.1), `_ENV` has no special status; the assignment just writes a global
into `_G`. The `setfenv( 1, _ENV )` call is what actually changes the function
environment so bare names resolve through the new table. Without it, everything
on LuaJIT silently goes into `_G`. Never remove this guard.

- **Public** functions: `function _M.foo( x )` — lives in the returned table.
- **Private** functions: `function helper( x )` — bare name, lives in `_ENV`, no `local`.
- `_MENV` exposes internals for testing, mocking, and environment reopening.
- No `return` at end of file — `package.loaded` is set up front.
- For simple utility modules where everything is public, `_M` can be `_ENV`.

**Reopening another module's environment:**
```lua
do local _ENV = mod._MENV  --[[ behaves as if this block is inside that file ]]  end
```

**Feature modules:** Instead of `if FEATURE_FLAG then …` scattered through
sub-modules, write a single `foo._features.bar` that reopens involved modules
and overrides/wraps functions. Main module returns a loader:
`foo = require "foo" { async = true }`.

### Modules with types

When a module defines a metatabled type, methods go on the **type table** (so
`__index` dispatch works), not on `_M`. The module table `_M` exposes only
constructors and free functions. This is the most common source of bugs when
following the module pattern — if methods are on `_M`, they won't be found
via `obj:method()` because `__index` points at the type table, not `_M`.

```lua
-- WRONG: methods on _M, but __index = Foo → obj:bar() fails
Foo = { __name = "Foo" } ; Foo.__index = Foo
function _M.new()  return setmetatable( {}, Foo )  end
function _M:bar()  return self.x  end  -- BROKEN for obj:bar()

-- RIGHT: methods on type table, _M only has constructor
Foo = { __name = "Foo" } ; Foo.__index = Foo
function Foo:bar()  return self.x  end  -- found via __index
function _M.new()  return setmetatable( {}, Foo )  end
```

If all public functions are methods on a single type, `_M` may only need `new`.
For modules with multiple types or free functions, `_M` holds the non-method API.

### Lua 5.5 note on modules

Lua 5.5 adds the `global` keyword. Chunks start with an implicit `global *`
(backwards-compatible). Inside any explicit `global` declaration, only declared
variables are allowed. The `_ENV`-based module pattern still works in 5.5 because
it manipulates `_ENV` directly, bypassing global resolution. No changes needed
to the module pattern above for 5.5.

If writing a 5.5-only strict module, you can add `global<const> *` at the top of
the chunk to make undeclared globals read-only, catching accidental global leaks.
But the `_ENV` pattern already achieves this isolation more portably.

---

## Formatting

- **Tabs for indentation, spaces for alignment.** One tab per depth level.
  Spaces only for lining things up — `=` in a table literal, comment columns,
  continuation lines. If a project already follows another convention, match
  the project.
- **Compact single-line blocks:** `if x then  do_thing()  end` — two spaces
  around the body.
- **Keep lines short.** ≤90 chars (at tab width 4) is a good target, not a
  hard limit.
- **Semicolons as separators:** ` ; ` (space-semicolon-space). A semicolon
  without a preceding space is always wrong.
- **Spaces inside call parens:** `f( x, y )`. No spaces for grouping: `(a + b)`.
- **Concise unless it hurts readability.** When two forms are equally clear,
  take the shorter one — but don't compress past the point of obviousness.

---

## Naming

| Form | Usage | Example |
|---|---|---|
| `ALL_CAPS` | Globals, constants | `MAX_RETRIES` |
| `CamelCase` | Types (metatables) | `Image`, `Player` |
| `lowerCase` | Everything else | `helper`, `processItem` |
| `_ALL_CAPS` | Lua-internal / magic | `_ENV`, `_NAME` |
| `_`, `_foo` | Unused / ignored | `_ok, err = ...` |
| `__name` | Metamethods (incl. custom) | `__add`, `__dup` |
| `foo_` | Caution signal | see below |

**Trailing underscore** has three meanings:
1. In data: private field.
2. In-place/mutating variant of a function (`map` → `map_`).
3. In modules: exposed low-level helper.

---

## Globals and Configuration

```lua
-- (a) FOO=x lua … — official params, Rust-like
FOO = tonumber( os.getenv "FOO" ) or default
-- (b) lua -e 'FOO="x"' … — rarely overridden params
FOO = FOO or default
FOO = (FOO == nil) and true or FOO  -- default true (avoid if possible)
```

---

## Functional Patterns

**Value first, varargs last.** Aligns with method syntax via `__index`.
```lua
function map( t, f, ... )
	local u = {}
	if type( f ) == "string" then
		for k, v in ipairs( t ) do  u[k] = v[f]( v, ... )  end
	else
		for k, v in ipairs( t ) do  u[k] = f( v, ... )  end
	end
	return setmetatable( u, getmetatable( t ) )
end
```

- String `f` = method dispatch. Otherwise `f` is a function or `__call`-able.
- Preserve metatables through transformations.
- Compose via nesting: `map( t, at, "key", string.upper )`.

**Parameter order:** value first, then required context, then optional, varargs
last. Never pad to reach a later parameter — `f( x, nil, nil, ctx )` means the
signature is wrong; move `ctx` forward.

**Varargs:** pass through, don't introspect. Use `select( '#', ... )` when you
need the count. Use `table.pack` only when you actually need the table.

**Closures:** fine for persistent state, long-lived iterators, or syntactic sugar
(`foo "x" { ... }`).

**Iterators:** prefer stateless > closure > coroutine. Lua 5.4+/5.5 generic `for`
accepts a 4th closeable state variable for cleanup.

**Multiple returns:** use freely for fixed/tuple shapes. For variable-length
results, return a table instead of building helpers to unpack them.

---

## Hot Paths

Hoist everything constant out of per-call code:

- **`require` at module level**, never inside a function. A cached `require` is
  still a hash lookup on every call.
- **Constant tables at module scope** — lookup tables, cost tables, dispatch
  tables. A table constructor inside a function allocates on every call.
- **Reuse buffers** in per-frame or per-tick loops instead of allocating a fresh
  table each pass.
- **No per-call closures** — pass varargs through instead.

Escalation order: readable Lua → optimized Lua → C. Each level keeps the
previous as its test oracle.

---

## Data Philosophy

Expose data-like structure as tables, not code.

- **Dispatch tables**, not if/elseif chains.
- **Table entries**, not nested callbacks.
- **Vararg tails**, not closures capturing extra args.
- **Nil handlers, not no-op functions.** Callers already guard with
  `if def.handler then …`, so a missing handler is simply absent — don't fill
  the slot with `function() end`.

**Tables:**
- Membership is a set, not an array: `{ MELEE = true }` for `roles.MELEE`, not
  `{ "MELEE" }` plus a linear scan. Build sets from lists with a small helper.
- Shallow copies are the norm. Deep copy is a method on the type, not generic.
- Don't mix dynamic hash metadata with array data. Fixed well-known fields
  (`.width`) alongside array data is fine.
- Append: `t[#t+1] = x` unless an index variable already exists. Explicit
  index if nils must be preserved as gaps.
- `table.move`: rarely needed — you're usually transforming, not just copying.

### Lua 5.5: `table.create`

5.5 adds `table.create( narray, nhash )` — equivalent to LuaJIT's
`table.new`. Use it when pre-allocating known-size tables in hot paths.
In LuaJIT, use `require "table.new"` for the same effect.

---

## Error Handling

- **Thrown errors** (`error()`) = bugs. Should crash. Don't catch.
- **Returned errors** (`nil, err`) = operational failures. Caller decides.
- `pcall` is rare. Use `xpcall` at trust/subsystem boundaries to capture traceback.
- If returned-error logic gets too complex, switch to `error`/`pcall` in that
  module. But beware: syntax/type errors are also caught by `pcall`. Use typed
  errors to ensure clean separation. At the module boundary, translate back:
  `pcall` → `return nil, err`, re-throwing non-operational Lua errors.
- **Typed errors:** tables (`{ type = "timeout", ... }`). No need for
  `type(err) == "table"` guard — string `__index` makes read access safe.

See `references/patterns.md` for `cpcall` (pcall + guaranteed cleanup).

---

## Metatables and OOP

Metatables always get `__name`:
```lua
Foo = { __name = "Foo" } ; Foo.__index = Foo
function Foo.new( x, y )  return setmetatable( { x = x, y = y }, Foo )  end
-- 5.4+ uses __name for tostring and error messages; LuaJIT ignores it.
-- Define __tostring for the same legibility on both.
function Foo.__tostring( self )  return "Foo(" .. self.x .. "," .. self.y .. ")"  end
```

- No class helpers, no `Class.extend()`, no base-class protocol.
- Inheritance only if actually needed: `setmetatable( Foo, { __index = Bar } )`.
  Prefer composition.
- Free functions for cross-type ops. Methods for per-type dispatch.
- Don't burn metamethods on sugar. `__index` for method lookup means you can't
  also use it for proxy/cache/lazy patterns. `__call` for construction blocks
  other uses.
- Keep metatables shallow, metamethods few, dispatch explicit.

**Live reload:** `Foo = Foo or { __name = "Foo" }` preserves the table across
reloads so existing instances see updated methods.

---

## Version-Specific Guidance

### LuaJIT (5.1 semantics)

- Add `setfenv` shim in module pattern (shown above).
- Avoid 5.3+ syntax (`//` integer division, `<const>`/`<close>` attributes) and
  5.5 keywords (`global`, `(...: args)`). Note that `goto`, `\x`/`\z`/`\u{}`
  escapes and `|`/`&`/`~`/`<<`/`>>` operators are LuaJIT extensions that work
  fine.
- `__name` is ignored (5.3+ metafield) — define `__tostring` for legible output.
- Use `bit` library for bitwise ops (not `bit32`).
- `table.new` via `require "table.new"` for pre-allocation.
- FFI available — but keep Lua-side code testable independently.

### Lua 5.5

- `global` is now a reserved word — don't use it as a variable name.
- For-loop variables are read-only. If you were mutating a loop variable,
  shadow it: `for k, v in pairs( t ) do  local k = k ; ... end`.
- `table.create( narray, nhash )` for pre-allocation.
- Named vararg tables: `function f( ...: args )` binds `args` as a proper
  table with `.n` field. Prefer this over `table.pack( ... )` in 5.5.
- `<close>` variables (from 5.4) still work. Define `__close` on metatables.
- Floats print with full round-trip precision by default.
- `utf8.offset` now returns the final position of the character as well.

### Writing portable LuaJIT + 5.5 code

- Use the `_ENV` module pattern with the `setfenv` guard.
- Avoid `global` declarations (reserved in 5.5, but the module pattern
  bypasses it anyway).
- Avoid mutating for-loop variables.
- Gate 5.5-only features behind version checks or feature modules.

---

## Strings

- Under-specify patterns; do post-checks. Don't force complex validation
  into Lua patterns.
- Use LPeg for anything beyond simple matching.

## Libraries

Vetted: **LPeg**, **lfs**, **LuaSocket**, **cjson**, **cqueues**,
**luaposix**. Beyond these, check quality and check with the user before adding.

---

## Use Cases

**Scripts / one-shot:** don't over-abstract. Use `_G` directly, skip module
machinery.

**Live coding / hot reload:**
- Anchor classes in `_G`: `_G.Foo = _G.Foo or { __name = "Foo" }`.
- Persistent state → global variables (survives reload).
- Disposable/cached state → locals / `_ENV` (reset on reload).
  A reload replaces closures wholesale; it can't swap just the code.
