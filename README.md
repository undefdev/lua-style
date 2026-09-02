# lua-style

An opinionated Lua style guide, packaged as a [Claude Code](https://claude.com/claude-code) skill.

Most Lua in the wild is unidiomatic — patterns ported verbatim from Python, JS,
or C++. Models trained on that corpus reproduce it. This skill defines the
idioms it should use instead, targeting **LuaJIT (5.1 semantics)** and **Lua 5.5**.

## Contents

- `SKILL.md` — the style guide: modules (`_ENV`-based), formatting, naming,
  functional patterns, data philosophy, error handling, metatables/OOP,
  version-specific guidance for LuaJIT vs 5.5.
- `references/patterns.md` — extended examples: `cpcall`, resource management,
  coroutines, testing, feature modules.
- `references/varargs-luajit.md` — measurements behind the LuaJIT vararg
  guidance, with the benchmark script (`references/varargs-bench.lua`).

## Install

The repo root *is* the skill directory, so clone it straight into place:

```sh
git clone https://github.com/undefdev/lua-style.git ~/.claude/skills/lua-style
```

Or keep the checkout wherever you like and symlink it:

```sh
git clone https://github.com/undefdev/lua-style.git /path/to/lua-style
ln -s /path/to/lua-style ~/.claude/skills/lua-style
```

Activate with `/lua-style`, or let Claude trigger it from the frontmatter
description when Lua comes up. Skills are read at session start, so a fresh
session is needed after changing them.
