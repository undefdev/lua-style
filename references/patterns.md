# Lua Patterns Reference

Detailed code examples for the lua-style skill. Read this file when you need
specific implementation patterns for error handling, resource management,
coroutines, testing, or feature modules.

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

Works on LuaJIT and 5.5 (both pass extra `xpcall` arguments through). The
results of `f` never touch a table, so `nil`s in the return list survive; only
the (small) argument list is packed, for the cleanup call.

```lua
do
	local unpack = unpack or table.unpack
	local function finish( c, args, ok, ... )
		c( unpack( args, 1, args.n ) )
		if not ok then  error( (...), 0 )  end
		return ...
	end
	function cpcall( f, c, ... )
		return finish( c, { n = select( '#', ... ), ... },
		               xpcall( f, debug.traceback, ... ) )
	end
end
```

`debug.traceback` returns non-string errors unchanged, so typed error tables
pass through `cpcall` intact; string errors arrive with a traceback appended.

Don't write the `{ xpcall( … ) } … unpack( ret, 2 )` variant: it drops trailing
`nil`s from the results, and `{ … }` on a vararg is a trace killer on LuaJIT
(see SKILL.md, Hot Paths). `cpcall` is not usually hot, but there's no reason
to pay for it.

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
- Mock via `_MENV`: `mod._MENV.httpRequest = mockFn`.
- Assertion helpers live in one shared module — never copy-pasted per file.

---

## Feature Modules

Instead of scattering `if FEATURE then ...` through code, use a feature module
that reopens other modules and patches them:

```lua
-- foo/_features/async.lua
return function( mods )
	local server = mods.server
	-- Reopen the server module's environment: bare names inside `patch`
	-- resolve through server._MENV, so its private helpers (asyncWrap)
	-- are reachable. Enclosing locals (server) stay visible as locals.
	local function patch( _ENV )
		local syncListen = server.listen
		function server.listen( addr, opts )
			return asyncWrap( syncListen, addr, opts )
		end
	end
	if setfenv then  setfenv( patch, server._MENV )  end
	patch( server._MENV )
end
```

The `_ENV` parameter does the reopening on 5.2+; `setfenv` does it on LuaJIT.
A `do local _ENV = … end` block only works on 5.2+ — on LuaJIT everything in it
lands in `_G`. Note that `_M` is a `local` in the module file, so it is *not*
reachable through `_MENV`; refer to the module table via `mods` instead.

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
