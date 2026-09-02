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

For detailed code examples and advanced patterns (`cpcall`, resource
management, coroutines, testing, feature modules), read `references/patterns.md`.
For the LuaJIT vararg measurements behind the Hot Paths section, see
`references/varargs-luajit.md`.

---

## Modules

Use `_ENV`-based modules, not `local M = {} ... return M`.

```lua
local _ENV = setmetatable( {}, { __index = _G } )
local _M = { _NAME = ..., _MENV = _ENV }
package.loaded[...] = _M
if setfenv then  setfenv( 1, _ENV )  end  -- LuaJIT compat (see below)
```

**Why `local _ENV`:** In Lua 5.2+, `_ENV` is the implicit upvalue through which
bare names resolve. A `local _ENV` shadows it for the rest of the chunk, so name
resolution switches to the new table. In LuaJIT (5.1), `_ENV` has no special
status — without `local`, the assignment writes a global `_G._ENV` that every
module overwrites, and any later bare `_ENV` in a module body resolves to
whichever module loaded last. With `local`, it is just a local on both.

**Why `setfenv` matters:** On LuaJIT, the local alone changes nothing about name
resolution. The `setfenv( 1, _ENV )` call is what actually changes the function
environment so bare names resolve through the new table. Without it, everything
on LuaJIT silently goes into `_G`. Never remove this guard.

- **Public** functions: `function _M.foo( x )` — lives in the returned table.
- **Private** functions: `function helper( x )` — bare name, lives in `_ENV`, no `local`.
- `_MENV` exposes internals for testing, mocking, and environment reopening.
- No `return` at end of file — `package.loaded` is set up front.
- For simple utility modules where everything is public, `_M` can be `_ENV`.

**Reopening another module's environment:** write the block as a function whose
parameter is named `_ENV`, and `setfenv` it on LuaJIT:
```lua
local function patch( _ENV )
	-- behaves as if this body were inside mod's file
end
if setfenv then  setfenv( patch, mod._MENV )  end
patch( mod._MENV )
```
In 5.2+ the `_ENV` parameter shadows the chunk's upvalue, so bare names resolve
through it. On LuaJIT the parameter is an ordinary local and `setfenv` does the
work. Do **not** use `do local _ENV = mod._MENV ... end` — it only works in
5.2+; on LuaJIT the block's definitions silently land in `_G`.

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
(backwards-compatible), so the module pattern above needs no changes for 5.5.

Don't use the keyword. Global declarations are checked on *names*, not on
`_ENV`: once a chunk contains any `global` declaration, every undeclared bare
name is a compile error ("variable 'z' not declared"), and `global<const> *`
turns the pattern's bare-name private functions (`function helper() end`) into
compile errors — `local _ENV` doesn't help, because the check happens before
`_ENV` is involved. Only explicit `_ENV.x = …` bypasses it. The keyword is also a
syntax error on every earlier version, so it excludes LuaJIT and 5.4 outright.

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
	local a, b = ...  -- unpack ONCE, before the loop; caps extras at two.
	                  -- Arbitrary n: generate per arity, see Hot Paths.
	local u = {}
	if type( f ) == "string" then
		for k, v in ipairs( t ) do  u[k] = v[f]( v, a, b )  end
	else
		for k, v in ipairs( t ) do  u[k] = f( v, a, b )  end
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
need the count. Pack into a table only when you actually need the table —
`table.pack( ... )` in 5.5, `{ n = select( '#', ... ), ... }` on LuaJIT. Never
use `...` inside a loop or a recursive call on LuaJIT — see Hot Paths.

**Closures:** fine for persistent state, long-lived iterators, or syntactic sugar
(`foo "x" { ... }`).

**Iterators:** prefer stateless > closure > coroutine. Lua 5.4+ generic `for`
accepts a 4th closeable state variable for cleanup.

**Multiple returns:** use freely for fixed/tuple shapes. For variable-length
results, return a table instead of writing helper functions that dissect a
vararg list.

---

## Hot Paths

Hoist everything constant out of per-call code:

- **`require` at module level**, never inside a function. A cached `require` is
  still a hash lookup on every call.
- **Constant tables at module scope** — lookup tables, cost tables, dispatch
  tables. A table constructor inside a function allocates on every call.
- **Reuse buffers** in per-frame or per-tick loops instead of allocating a fresh
  table each pass.
- **No per-call closures** — but on LuaJIT, a vararg tail is *not* the cheaper
  alternative (see below). Fixed parameters are.

### Varargs on LuaJIT

LuaJIT's JIT compiles `...` only when the call that created the vararg frame is
on the same trace, i.e. when it knows the count. Whenever a trace *starts*
inside a vararg function — any hot loop inside it, or recursion through it —
every multi-value use of `...` aborts the trace (`NYI: bytecode VARG`), the
function gets blacklisted and the whole loop runs interpreted. That covers
`f( v, ... )`, `{ ... }` and `return ...`. `select( '#', ... )`,
`select( k, ... )` and `local a, b = ...` still compile.

Measured (see `references/varargs-luajit.md`): `f( v, ... )` in a loop is
3–4× slower than fixed arity and slower than a per-call closure; a recursive
vararg tail is 30× slower; `{ ... }` in the callee is 60×. Lua 5.5 shows at
most ~2× for any of these, so this is LuaJIT-specific.

In order of preference:

1. **Known arity at write time** → write the parameters. No `...`.
2. **Vararg function containing a loop** → `local a, b = ...` at function
   entry, then use the locals. Compiles fine.
3. **Arity known only at runtime, stable per call site** → generate one
   fixed-arity function per count with `loadstring`/`load` via string
   substitution, and cache it by `n`. Generated code runs at hand-written speed.
   ```lua
   local specialized = {}
   function forArity( n )
   	if specialized[n] then  return specialized[n]  end
   	local args = {}
   	for i = 1, n do  args[i] = "a" .. i  end
   	local list = table.concat( args, ", " )
   	local src = ("return function( f, %s ) return f( %s ) end"):format( list, list )
   	specialized[n] = assert( (loadstring or load)( src ) )()
   	return specialized[n]
   end
   ```

Escalation order: readable Lua → optimized Lua → C. Each level keeps the
previous as its test oracle.

---

## Data Philosophy

Expose data-like structure as tables, not code.

- **Dispatch tables**, not if/elseif chains.
- **Table entries**, not nested callbacks.
- **Extra parameters**, not closures capturing extra args. A vararg tail is
  fine in the signature, but unpack it to locals before any loop (LuaJIT).
- **Nil handlers, not no-op functions.** Callers already guard with
  `if def.handler then …`, so a missing handler is simply absent — don't fill
  the slot with `function() end`.

**Tables:**
- Membership is a set, not an array: `{ MELEE = true }` for `roles.MELEE`, not
  `{ "MELEE" }` plus a linear scan. Build sets from lists with a small helper.
- Shallow copies are the norm. Deep copy is a method on the type, not generic.
- Don't mix dynamic hash metadata with array data. Fixed well-known fields
  (`.width`) alongside array data is fine.
- Append: `t[#t+1] = x` unless an index variable already exists. Use an
  explicit index if nils must be preserved as gaps.
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
- **Typed errors:** tables (`{ type = "timeout", ... }`). No need for a
  `type(err) == "table"` guard — the string type's `__index` makes read access
  on a plain string error safe (`err.type` is `nil`). Avoid field names that
  collide with string library functions (`len`, `sub`, `format`, `rep`, `find`,
  `match`, `byte`): on a string error those return a function, not `nil`.

See `references/patterns.md` for `cpcall` (pcall + guaranteed cleanup).

---

## Metatables and OOP

Metatables always get `__name`:
```lua
Foo = { __name = "Foo" } ; Foo.__index = Foo
function Foo.new( x, y )  return setmetatable( { x = x, y = y }, Foo )  end
-- 5.3+ uses __name for tostring and error messages; LuaJIT ignores it.
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

**Live reload:** `_G.Foo = _G.Foo or { __name = "Foo" }` preserves the table
across reloads so existing instances see updated methods. It must be anchored
in `_G`: inside an `_ENV` module a bare `Foo = Foo or …` never finds the old
table, because the module's `_ENV` is rebuilt on every reload.

---

## Version-Specific Guidance

### LuaJIT (5.1 semantics)

- Add `setfenv` shim in module pattern (shown above).
- Avoid 5.3+ syntax (`//` integer division, `<const>`/`<close>` attributes) and
  the 5.5 `global` keyword. `goto` and `\x`/`\z`/`\u{}` escapes are LuaJIT
  extensions that work fine.
- Bitwise operators `|`/`&`/`~`/`<<`/`>>` parse on current LuaJIT 2.1 rolling
  releases but **not** on 2.1.0-beta3, which many distros and OpenResty still
  ship — and they have 32-bit `bit`-library semantics (`1 << 62` wraps). Use the
  `bit` library (not `bit32`) when either matters.
- `__name` is ignored (5.3+ metafield) — define `__tostring` for legible output.
- Varargs are compiled only with a known count — see Hot Paths. No `...` in
  loops or recursion.
- `table.new` via `require "table.new"` for pre-allocation.
- FFI available — but keep Lua-side code testable independently.

### Lua 5.5

- `global` is now a reserved word — don't use it as a variable name.
- For-loop variables are read-only. If you were mutating a loop variable,
  shadow it: `for k, v in pairs( t ) do  local k = k ; ... end`.
- `table.create( narray, nhash )` for pre-allocation.
- There is no named-vararg syntax (`(...: args)` is a syntax error). Use
  `table.pack( ... )` when you need the table.
- `<close>` variables (from 5.4) still work. Define `__close` on metatables.
- Floats print with full round-trip precision by default.
- `utf8.offset` now returns the final position of the character as well.

### Writing portable LuaJIT + 5.5 code

- Use the `local _ENV` module pattern with the `setfenv` guard, and the
  `patch( _ENV )` + `setfenv` form for reopening.
- Avoid `global` declarations (a syntax error before 5.5, and they break the
  module pattern's bare-name privates — see the 5.5 module note).
- Avoid mutating for-loop variables.
- Gate 5.5-only *library* features behind version checks or feature modules.
  Gate 5.5-only *syntax* with `load[[ … ]]` — a runtime check can't stop the
  parser, but `load` returns `nil, err` instead of failing the whole chunk.

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
