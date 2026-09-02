-- Benchmark behind SKILL.md → Hot Paths → "Varargs on LuaJIT".
-- Run:  luajit varargs-bench.lua 2e7      lua5.5 varargs-bench.lua 2e6
-- Trace aborts:  luajit -jv varargs-bench.lua 2e5 2>&1 | grep -- '--'
local clock = os.clock
local loadstring = loadstring or load
local N = tonumber( arg and arg[1] ) or 2e6

local function bench( name, f )
	local t0 = clock() ; local r = f() ; local dt = clock() - t0
	print( string.format( "%-46s %7.3fs  %s", name, dt, tostring( r ) ) )
end

-- Non-inlinable callee: chosen from a table by data, so the JIT can't fold it.
local ops = {
	function( v, a, b )  return v + a + b  end,
	function( v, a, b )  return v * a - b  end,
}
local data = {} ; for i = 1, 100 do  data[i] = i  end

-- 1) hot loop INSIDE a vararg function --------------------------------------
local function mapV( t, f, ... )            -- ... used in the loop → NYI VARG
	local u = {}
	for k, v in ipairs( t ) do  u[k] = f( v, ... )  end
	return u
end
local function mapL( t, f, ... )            -- unpacked to locals first → compiles
	local a, b = ...
	local u = {}
	for k, v in ipairs( t ) do  u[k] = f( v, a, b )  end
	return u
end
local function mapF( t, f, a, b )           -- fixed arity
	local u = {}
	for k, v in ipairs( t ) do  u[k] = f( v, a, b )  end
	return u
end
local function mapC( t, f )                 -- caller passes a closure
	local u = {}
	for k, v in ipairs( t ) do  u[k] = f( v )  end
	return u
end
local mapG = assert( loadstring( [[     -- generated for arity 2
	local ipairs = ipairs
	return function( t, f, a, b )
		local u = {}
		for k, v in ipairs( t ) do  u[k] = f( v, a, b )  end
		return u
	end ]] ) )()

bench( "1a map: f(v, ...) in loop", function()
	local s = 0
	for i = 1, N / 100 do  s = s + mapV( data, ops[i % 2 + 1], i, 2 )[50]  end
	return s
end )
bench( "1b map: local a, b = ... then f(v, a, b)", function()
	local s = 0
	for i = 1, N / 100 do  s = s + mapL( data, ops[i % 2 + 1], i, 2 )[50]  end
	return s
end )
bench( "1c map: fixed arity f(v, a, b)", function()
	local s = 0
	for i = 1, N / 100 do  s = s + mapF( data, ops[i % 2 + 1], i, 2 )[50]  end
	return s
end )
bench( "1d map: per-call closure", function()
	local s = 0
	for i = 1, N / 100 do
		local f, a, b = ops[i % 2 + 1], i, 2
		s = s + mapC( data, function( v )  return f( v, a, b )  end )[50]
	end
	return s
end )
bench( "1e map: codegen-specialized arity 2", function()
	local s = 0
	for i = 1, N / 100 do  s = s + mapG( data, ops[i % 2 + 1], i, 2 )[50]  end
	return s
end )

-- 2) recursion carrying a vararg tail ---------------------------------------
local function recV( n, acc, ... )
	if n == 0 then  return acc  end
	return recV( n - 1, acc + (...), ... )
end
local function recF( n, acc, a, b, c )
	if n == 0 then  return acc  end
	return recF( n - 1, acc + a, a, b, c )
end
bench( "2a recursion: vararg tail, depth 20", function()
	local s = 0
	for i = 1, N / 20 do  s = s + recV( 20, 0, i, 1, 2 )  end
	return s
end )
bench( "2b recursion: fixed arity, depth 20", function()
	local s = 0
	for i = 1, N / 20 do  s = s + recF( 20, 0, i, 1, 2 )  end
	return s
end )

-- 3) arity varies per call site: select-loop vs codegen per arity -----------
local function sumV( ... )
	local s = 0
	for i = 1, select( '#', ... ) do  s = s + (select( i, ... ))  end
	return s
end
local sums = {}
for n = 1, 4 do
	local a = {} ; for i = 1, n do  a[i] = "a" .. i  end
	sums[n] = assert( loadstring( ("return function( %s ) return %s end"):format(
		table.concat( a, ", " ), table.concat( a, " + " ) ) ) )()
end
bench( "3a select('#')/select(i) loop, arity 1..4", function()
	local s = 0
	for i = 1, N do
		local m = i % 4
		if m == 0 then  s = s + sumV( i )
		elseif m == 1 then  s = s + sumV( i, 1 )
		elseif m == 2 then  s = s + sumV( i, 1, 2 )
		else  s = s + sumV( i, 1, 2, 3 )  end
	end
	return s
end )
bench( "3b codegen per arity, arity 1..4", function()
	local s = 0
	for i = 1, N do
		local m = i % 4
		if m == 0 then  s = s + sums[1]( i )
		elseif m == 1 then  s = s + sums[2]( i, 1 )
		elseif m == 2 then  s = s + sums[3]( i, 1, 2 )
		else  s = s + sums[4]( i, 1, 2, 3 )  end
	end
	return s
end )

-- 4) packing varargs into a table -------------------------------------------
bench( "4a {...} in callee", function()
	local s = 0
	local function f( ... )  local t = { ... } ; return t[1] + #t  end
	for i = 1, N do  s = s + f( i, 1, 2 )  end
	return s
end )
bench( "4b { n = select('#', ...), ... } in callee", function()
	local s = 0
	local function f( ... )  local t = { n = select( '#', ... ), ... } ; return t[1] + t.n  end
	for i = 1, N do  s = s + f( i, 1, 2 )  end
	return s
end )
bench( "4c fixed arity, no table", function()
	local s = 0
	local function f( a, b, c )  return a + 3  end
	for i = 1, N do  s = s + f( i, 1, 2 )  end
	return s
end )
