---
layout: lua-in-rust
title: "Lua in Rust: Combinatory parsing"
categories: "lua-in-rust"
---

The first order of business is to parse text and turn it into Lua syntax tree.

Combinatory parsing
===================

From my days of [Haskell](https://haskell.org) programming I know an instrument
called [combinatory parsing](https://en.wikipedia.org/wiki/Parser_combinator) for
creating recursive descent parsers. Parser combinators allow
to produce very readable parsers without using parser generator tools like
[flex](https://en.wikipedia.org/wiki/Flex%20lexical%20analyser) and
[yacc](https://en.wikipedia.org/wiki/Yacc).

The main idea is that parser is a function from an input to the resulting value together
with the rest of input, and since it's just a function, you can write it by hand, or you can
take 2 parsers and combine it together like 2 functions, or (if your language treats functions
as first-class citizens) you can write a function that takes parser as an input and outputs
another parser.

Rust implementation
===================

In Rust we can write parsers like that:
{% highlight rust %}
fn parse<'a, T>(input: &'a str) -> Option<(T, &'a str)> {
  ...
}
{% endhighlight %}
A function that takes a string slice, and optionally returns a `T` with the rest of the slice.
I choose to explicitly annotate lifetimes because it makes it easier for me to understand them.
Here by using the same `'a` on both slices I want to express that they point to one and the same
data (albeit to different portions of it).

A portion of basic parsers:
* Empty parser: always succeeds, does not consume any input.
{% highlight rust %}
fn empty_parser<'a>(input: &'a str) -> Option<((), &'a str)> {
  Some(((), input))
}
{% endhighlight %}
* Failing parser: never succeeds.
{% highlight rust %}
fn fail_parser<'a>(input: &'a str) -> Option<((), &'a str)> {
  None
}
{% endhighlight %}
* A parser that checks next character in `input` and if it satisfies `f` returns it.
{% highlight rust %}
fn satisfies<'a>(f: impl Fn(char) -> bool,
                 input: &'a str) -> Option<(char, &'a str)> {
    // Here I mean to say "take next character if any". And if there isn't any,
    // the function immediately returns None. That's what ? does.
    let c = input[0..].chars().next()?;
    if f(c) {
        // If character c is alright, return it and forward input 1 character.
        Some((c, &input[1..]))
    } else {
        // Otherwise just fail.
        None
    }
}
{% endhighlight %}
`impl Fn(char) -> bool` means "any type that implements trait `Fn(char) -> bool`" and trait
`Fn(char) -> bool` is a trait that is implemented by closures that take `char` argument and
produce `bool`.
* A parser that takes two parsers and applies them one after another.
{% highlight rust %}
fn seq<'a, T1, T2>(p1: impl Fn(&'a str) -> Option<(T1, &'a str)>,
                   p2: impl Fn(&'a str) -> Option<(T2, &'a str)>,
                   input: &'a str) -> Option<((T1, T2), &'a str)> {
    // Try running p1.
    let (p1_result, input) = p1(input)?;
    // Try running p2 on the rest of the input from p1.
    let (p2_result, input) = p2(input)?;
    // And aggregate the result returning the rest of the input from p2.
    Some(((p1_result, p2_result), input))
}
{% endhighlight %}
Just like in a previous parser, this one takes functions as arguments, however, this time
this functions are actually parsers. So `seq` is the first example of a parser combinator.

Now, let's try to use this parser library.
{% highlight rust %}
fn char_parser<'a>(c: char, input: &'a str) -> Option<(char, &'a str)> {
  satisfies(|in_c| in_c == c, input)
}

// This parser expects input to start with string "ab"
fn ab_parser<'a>(input: &'a str) -> Option<((char, char), &'a str)> {
    seq(|input| char_parser('a', input), |input| char_parser('b', input), input)
}
{% endhighlight %}

I don't like this `ab_parser` much: it's too verbose with explicit `input` passing.

Making it more functional
=========================

So, what if our parser functions stop being parsers themselves and would return parsers instead?

{% highlight rust %}
fn empty_parser<'a>() -> impl Fn(&'a str) -> Option<((), &'a str)> {
    |input| Some(((), input))
}

fn fail_parser<'a>() -> impl Fn(&'a str) -> Option<((), &'a str)> {
    |input| None
}

fn satisfies<'a>(f: impl Fn(char) -> bool) ->
                 impl Fn(&'a str) -> Option<(char, &'a str)> {
    // `move` here means to move f into the closure instead of borrowing it.
    move |input| {
        let c = input[0..].chars().next()?;
        if (f(c)) {
            Some((c, &input[1..]))
        } else {
            None
        }
    }
}

fn seq<'a, T1, T2>(p1: impl Fn(&'a str) -> Option<(T1, &'a str)>,
                   p2: impl Fn(&'a str) -> Option<(T2, &'a str)>) ->
                   impl Fn(&'a str) -> Option<((T1, T2), &'a str)> {
    move |input| {
        let (p1_result, input) = p1(input)?;
        let (p2_result, input) = p2(input)?;
        Some(((p1_result, p2_result), input))
    }
}
{% endhighlight %}

What changed here is `input: &'a str` has migrated to the return type with `impl Fn(&'a str)` and into
the function body as `|input|`.
This means that `empty_parser`, `fail_parser`, `satisfies` and `seq` now return closures that take `&'a str`
and return `Option<(..., &'a str)>`.
`impl` on the return type position is interesting: it's so-called opaque type. It's in fact some concrete
type but users of the function only know that implements a trait `Fn(...) -> ...`.

The library usage now looks like:
{% highlight rust %}
fn char_parser<'a>(c: char) -> impl Fn(&'a str) -> Option<(char, &'a str)> {
    satisfies(move |in_c| in_c == c)
}

fn ab_parser<'a>() -> impl Fn(&'a str) -> Option<((char, char), &'a str)> {
    seq(char_parser('a'), char_parser('b'))
}
{% endhighlight %}

Way nicer.

Day 1 and it's already time for hacks
=====================================

What's not so nice is all the `impl Fn(&'a str) -> Option<(..., &'a str)>` lying around.
What I really want is to make a trait alias, but it's not yet done (see [here](https://github.com/rust-lang/rust/issues/41517)). So, time for a hack:
{% highlight rust %}
trait Parser<'a, T>: Fn(&'a str) -> Option<(T, &'a str)> {}
impl<'a, T, F : Fn(&'a str) -> Option<(T, &'a str)>> Parser<'a, T> for F {}
{% endhighlight %}
I'm creating a brand new empty trait `Parser<'a, T>` that extends `Fn(&'a str) -> Option<(T, &'a str)>` and also add an implementation
of `Parser<'a, T>` to all types `F` that implement `Fn(&'a str) -> Option<(T, &'a str)>`. This way all types that
implement `Parser<'a ,T>` implement `Fn(&'a str) -> Option<(T, &'a str)>` (because of inheritance) and all types
that implement `Fn(&'a str) -> Option<(T, &'a str)>` implement `Parser<'a, T>` (because `impl` rule explicitly says so).

{% highlight rust %}
fn empty_parser<'a>() -> impl Parser<'a, ()> {
    |input| Some(((), input))
}

fn fail_parser<'a>() -> impl Parser<'a, ()> {
    |input| None
}

fn satisfies<'a>(f: impl Fn(char) -> bool) -> impl Parser<'a, char> {
    move |input| {
        let c = input[0..].chars().next()?;
        if (f(c)) {
            Some((c, &input[1..]))
        } else {
            None
        }
    }
}

fn seq<'a, T1, T2>(p1: impl Parser<'a, T1>,
                   p2: impl Parser<'a, T2>) ->
                   impl Parser<'a, (T1, T2)> {
    move |input| {
        let (p1_result, input) = p1(input)?;
        let (p2_result, input) = p2(input)?;
        Some(((p1_result, p2_result), input))
    }
}
{% endhighlight %}

Noise at the type level is eliminated.
