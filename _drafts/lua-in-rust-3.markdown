---
layout: post
title: "Lua in Rust 3"
categories: "lua-in-rust"
---

Now it's the time to define Lua syntax.

To start off, I'm doing lexing into vector of tokens.

Here's [syntax](https://github.com/projedi/lua-in-rust/commit/7300733e4baced3498779d720c8a7e8919e507dd) and
here's [parser](https://github.com/projedi/lua-in-rust/commit/cd08246a81ab5e1935393b8ab773540c7f6b6aeb).

Everything pretty much follows [Lua Lexical Conventions](http://www.lua.org/manual/5.1/manual.html#2.1).

Of note is the definition of `Keyword` and `OtherToken`. I created a macro `plain_enum` that expects an
enum description together with string representation of each item and generates the enum, gives the ability
to iterate over it's items, convert those items to string, and view them in a sorted collection, which is
used by the parser.
