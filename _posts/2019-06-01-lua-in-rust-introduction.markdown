---
layout: post
title: "Lua in Rust: Introduction"
categories: "lua-in-rust"
---

This begins a series dedicated to creating a JIT compiler for [Lua 5.1](http://www.lua.org) in [Rust 1.35](https://www.rust-lang.org).

This is my first project in Rust, I've never used it before, so it'll be full of mistakes and unidiomatic code. Also,
I'm going to avoid using any 3rd party crate unless I absolutely have to: this is a project to learn Rust after all.

The repo is [here](https://github.com/projedi/lua-in-rust).

The initial setup
=================

The first thing to do is to setup reference implementation ideally with testing infrastructure. This makes
it easy to compare custom implementation with the reference.

For the reference I've chosen [Lua 5.1.5](http://www.lua.org/ftp/lua-5.1.5.tar.gz),
[Lua 5.1 test suite](http://www.lua.org/tests/lua5.1-tests.tar.gz) and [LuaJIT 2.0.5](http://luajit.org/download/LuaJIT-2.0.5.tar.gz).
I included LuaJIT in the mix to compare the performance to. And since 2.0.5 is Lua 5.1 compatible, I've selected the appropriate version
of Lua itself. [Here](https://github.com/projedi/lua-in-rust/tree/d5dc42f0bb7dcb3bfc6736aad622d4381658615c)'s the state of the tree with
all things imported.

Naturally, things didn't work out from the get go. I had to make [modifications](https://github.com/projedi/lua-in-rust/commit/0b7229e31e1349aef63203df333fef84b8cdfd7b)
to make things work and the majority of tests to pass:
1. To make LuaJIT build on macOS I needed to change deployment target from the old 10.04 to 10.10.
2. LuaJIT REPL outputs it's header to stdout while Lua proper expect it to go to stderr. Fixed by sending stuff to stderr.
3. Lua on Linux uses readline which outputs to stdout everything from stdin. Tests are not expecting that. Fixed by turning readline off.
4. Lua tests include native libraries which didn't build on macOS.
5. One test doesn't pass on Lua proper, had to blacklist it, because I frankly don't understand what's going on.
6. And quite a number of tests don't pass on LuaJIT, blacklisted all of them.

Next steps
==========

{% assign posts = site.categories.lua-in-rust | sort: "date", "last" %}
{% for post in posts %}
1. [{{post.title}}]({{ site.baseurl }}{{post.url}})
{% endfor %}
