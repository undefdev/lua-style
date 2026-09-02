# Varargs on LuaJIT: measurements

Evidence for SKILL.md → Hot Paths → "Varargs on LuaJIT". Reproduce with
`varargs-bench.lua` in this directory.

## Mechanism

LuaJIT's trace recorder handles `...` in two situations:

- **Vararg frame created on the trace.** The call into the vararg function was
  recorded, so the JIT knows the exact argument count and compiles `...` like
  fixed parameters. This is why a trivial `function wrap( ... ) return g( ... )
  end` called from a hot loop is free.
- **Trace starts inside the vararg function.** The argument count is unknown.
  Only `select( '#', ... )`, `select( k, ... )` and a fixed-count `local a, b =
  ...` are compiled. Every multi-value use — `f( v, ... )`, `{ ... }`,
  `return ...` — aborts the trace with `NYI: bytecode VARG`. After a few aborts
  the function is blacklisted and the loop stays in the interpreter.

The second case is what a hot loop *inside* a vararg function, or recursion
*through* one, always hits.

## Numbers

macOS arm64, LuaJIT 2.1 rolling (`jit.version_num` 20199, Sept 2026) at
`N = 2e7`; Lua 5.5.1 at `N = 2e6` (10× fewer iterations). Callee chosen from a
table by data so the JIT cannot fold it.

| Case | LuaJIT | vs fixed | Lua 5.5 | vs fixed |
|---|---|---|---|---|
| map: `f( v, ... )` in loop | 0.434s | 3.6× | 0.093s | 1.0× |
| map: `local a, b = ...` then `f( v, a, b )` | 0.129s | 1.1× | 0.093s | 1.0× |
| map: fixed arity `f( v, a, b )` | 0.122s | 1× | 0.092s | 1× |
| map: per-call closure | 0.165s | 1.4× | 0.124s | 1.3× |
| map: codegen-specialized, arity 2 | 0.123s | 1.0× | 0.092s | 1.0× |
| recursion: vararg tail, depth 20 | 0.395s | 30× | 0.053s | 1.4× |
| recursion: fixed arity, depth 20 | 0.013s | 1× | 0.039s | 1× |
| `select('#')`/`select(i)` loop, arity 1..4 | 0.323s | 3.4× | 0.248s | 4.2× |
| codegen per arity, arity 1..4 | 0.094s | 1× | 0.059s | 1× |
| `{ ... }` in callee | 1.191s | 63× | 0.179s | 5.8× |
| `{ n = select('#', ...), ... }` in callee | 1.871s | 98× | 0.338s | 11× |
| fixed arity, no table | 0.019s | 1× | 0.031s | 1× |

Trace aborts reported by `luajit -jv` for the slow cases:

```
varargs-bench.lua:23 -- NYI: bytecode VARG          (map with f( v, ... ))
varargs-bench.lua:52 -- blacklisted at :23          (caller gives up too)
varargs-bench.lua:67 -- NYI: bytecode FNEW          (per-call closure creation)
```

## Takeaways

1. The skill's old advice "no per-call closures — pass varargs through" was
   inverted for LuaJIT: the closure version beat the vararg-tail version.
   Fixed parameters beat both.
2. `local a, b = ...` at function entry is the cheap fix for a vararg function
   that contains a loop. It costs nothing measurable.
3. When the arity is only known at runtime, generating one fixed-arity
   function per count (string substitution + `loadstring`/`load`, cached by
   `n`) reaches hand-written speed. On Lua 5.5 this still pays off for the
   select-loop case (4×), so the technique is not LuaJIT-only — only the
   penalties for plain pass-through are.
4. Packing `...` into a table is the worst option on both VMs. On LuaJIT it is
   two orders of magnitude.
