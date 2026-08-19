# Lua Patterns Reference

Detailed code examples for the lua-style skill. Read this file when you need
specific implementation patterns for error handling, resource management, OOP,
coroutines, or testing.

## Table of Contents

1. [cpcall — pcall with guaranteed cleanup](#cpcall)
2. [Resource Management](#resource-management)
3. [Coroutines](#coroutines)
4. [Testing](#testing)
5. [Feature Modules](#feature-modules)

---

## cpcall

`cpcall` = pcall + guaranteed cleanup. The cleanup function `c` always runs,
even if `f` errors. If `f` errored, the error is re-thrown after cleanup.

**LuaJIT-compatible** (no `table.pack`/`table.unpack`):

```lua
do
  local unpack = unpack or table.unpack
  function cpcall( f, c, ... )
    -- xpcall returns ok, result... — we capture into a table manually
    -- because LuaJIT lacks table.pack.
    local ret = { xpcall( f, debug.traceback, ... ) }
    c( ... )
    if not ret[1] then  error( ret[2], 0 )  end
    return unpack( ret, 2 )
  end
end
```

Note: this version drops nils in the return tail (since `#ret` won't count
trailing nils). If you need nil-safe returns, use a count variable:

```lua
do
  local unpack = unpack or table.unpack
  function cpcall( f, c, ... )
    local n = select( "#", ... )
    local ret_n
    local ret = { xpcall( f, function( err )
      ret_n = 0  -- signal error
      return debug.traceback( err )
    end, ... ) }
    c( ... )
    if not ret[1] then  error( ret[2], 0 )  end
    return unpack( ret, 2 )
  end
end
```

For the rare case where you truly need nil-preserving returns across pcall on
LuaJIT, consider using `select('#', ...)` on the xpcall results via a wrapper,
or just return a table from `f` instead of multiple values.

---

## Resource Management

### Lua 5.4 / 5.5: `<close>` variables

Define `__close` on metatables. Call `coroutine.close( co )` after failed
resume — don't rely on GC.

```lua
Conn = { __name = "Conn" } ; Conn.__index = Conn
function Conn.__close( self )  self:disconnect()  end
function Conn.new( host )
  return setmetatable( { host = host, sock = connect( host ) }, Conn )
end

-- Usage:
local conn <close> = Conn.new( "localhost" )
-- conn:disconnect() called automatically when scope exits
```

### Pre-5.4 / LuaJIT: `with`-style wrappers using `cpcall`

```lua
function withOpenFile( fname, mode, func )
  return cpcall( func, io.close, assert( io.open( fname, mode ) ) )
end

-- Usage:
withOpenFile( "data.txt", "r", function( f )
  for line in f:lines() do  process( line )  end
end )
```

---

## Coroutines

- Define a communication protocol: `yield( kind, payload )`.
- Prefer flat dispatch: one manager, N workers, nesting depth = 1.
- Yields pass through all intermediate frames — the protocol is a property of
  the entire call tree, not just the coroutine body.

```lua
-- Simple task system with typed yields
function worker( id )
  while true do
    local task = coroutine.yield( "ready", id )
    local result = doWork( task )
    coroutine.yield( "done", { id = id, result = result } )
  end
end

function scheduler( tasks )
  local workers = {}
  for i = 1, NUM_WORKERS do
    workers[i] = coroutine.create( worker )
    coroutine.resume( workers[i], i )  -- prime
  end
  -- ... dispatch loop using kind/payload protocol
end
```

**Wrapping main in a coroutine** enables post-mortem inspection:
`debug.getlocal( co, i, j )` on errored thread, stack still intact.

---

## Testing

Tests as plain tables, not framework callbacks.

```lua
tests.funcname = {
  { "description", function() assert( ... ) end },
  { "another case", function() assert( ... ) end },
}
```

- Group by function. Positional fields: `[1]` = name, `[2]` = test fn.
- Setup/cleanup as named fields on group or entry.
- Filter by function (`tests[name]`), by marker string, or by attributes.
- Mock via `_MENV`: `mod._MENV.http_request = mock_fn`.

---

## Feature Modules

Instead of scattering `if FEATURE then ...` through code, use a feature module
that reopens other modules and patches them:

```lua
-- foo/_features/async.lua
return function( mods )
  -- Reopen the server module and wrap its listen function
  do local _ENV = mods.server._MENV
    local sync_listen = _M.listen
    function _M.listen( addr, opts )
      return async_wrap( sync_listen, addr, opts )
    end
  end
end
```

Main module returns a loader:

```lua
-- foo/init.lua
return function( opts )
  local mods = {
    server = require "foo.server",
    client = require "foo.client",
  }
  if opts.async then  require "foo._features.async" ( mods )  end
  return mods
end

-- Usage: foo = require "foo" { async = true }
```
