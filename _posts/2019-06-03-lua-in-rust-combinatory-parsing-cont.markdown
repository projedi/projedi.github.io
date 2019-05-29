---
layout: post
title: "Lua in Rust: Combinatory parsing (cont.)"
categories: "lua-in-rust"
---

Continued exploration of combinatory parsing in Rust.

Extracting parsed string
========================

Thinking some more, about parsing, I arrived at the need to create a parser that
would run a given parser and return a consumed string.
{% highlight rust %}
pub fn parsed_string<'a, T>(p: impl Parser<'a, T>) -> impl Parser<'a, (T, &'a str)> {
    move |input| {
        let (p_result, p_input) = p(input)?;
        Some(((p_result, ???), p_input))
    }
}
{% endhighlight %}
It's going to be useful in two places: parsing long brackets and numbers. Long brackets
are a form of "raw" string literals that is they do not contain any escape characters or anything.
So, I'd be able to write a parser that does nothing and only waits for the closing bracket to appear and
then wrap it in `parsed_string` which would give me precisely the string inside the brackets.
As for the numbers: I'd be able to parse numbers as Lua defines them and then give the resulting string
to Rust stdlib to parse the number for me.

Now, I don't know if there's a way to obtain an `x` from `a` and `b`, when `a = x + b` and all of them
are `&'a str`, so I decided to make it simple:
{% highlight rust %}
#[derive(Copy, Clone)]
struct ParserState<'a> {
    input: &'a str,
    index: usize,
}

trait Parser<'a, T>: Fn(ParserState<'a>) -> Option<(T, ParserState<'a>)> {}

impl<'a, T, F: Fn(ParserState<'a>) -> Option<(T, ParserState<'a>)>> Parser<'a, T> for F {}

fn run_parser<'a, T>(input: &'a str, p: impl Parser<'a, T>) -> Option<T> {
    let s = ParserState { input, index: 0 };
    match p(s) {
        Some((result, s)) => Some(result),
        None => None,
    }
}

fn satisfies<'a>(f: impl Fn(char) -> bool) -> impl Parser<'a, char> {
    move |s: ParserState<'a>| {
        let c = s.input[s.index..].chars().next()?;
        if f(c) {
            let mut out_s = s;
            out_s.index += 1;
            return Some((c, out_s));
        }
        return None;
    }
}

fn parsed_string<'a, T>(p: impl Parser<'a, T>) -> impl Parser<'a, (T, &'a str)> {
    move |s| {
        let (p_result, p_s) = p(s)?;
        Some(((p_result, &s.input[s.index..p_s.index]), p_s))
    }
}
{% endhighlight %}
Instead of passing input around I now pass `ParserState` around, which contains an immutable `input` and
an `index` into it. `satisfies` now moves an `index` and `parsed_string` is able to use indices before and
after `p` to get parsed string. And I also added a helper `run_parser` that hides `ParserState` from the clients.

parser_lib
==========

[Here](https://github.com/projedi/lua-in-rust/commit/8091ba06d56ae788cdfa89333d2a5835a5a3a44a)'s all the code I ended up with. There're also some additional combinators I didn't mension here:
* `fmap(f, p)` (I just named it like it's in Haskell) that applies a function `f` to the result of parser `p`. If parser `p` fails, `fmap(f, p)` also fails; if parser `p` gives `x`, `fmap(f, p)` gives `f(x)` and consumes exactly what `p` consumes.
* `choice(p1, p2)` that selects the first passing parser of the two.
* `many(p)` that applies `p` as many times as it can collecting the results and returning them in a vector.
* `many1(p)` that is just like `many` but requires `p` to pass at least once.
* `string_parser(expected_str)` that expects input to start with `expected_str`.

Everything is a Box
===================

Tired but feeling a sense of accomplishment, I tried one last thing:
{% highlight rust linenos %}
#[test]
fn test_complex_parser() {
    let mut p = fmap(|_| 3, empty_parser());
    assert_eq!(run_parser_impl("abc def", &p), Some((3, "abc def")));
    p = fmap(|x: (i32, ())| x.0, seq(p, fail_parser()));
    assert_eq!(run_parser_impl("abc def", &p), None);
    let q = fmap(|_| 5, string_parser("abc"));
    assert_eq!(run_parser_impl("abc def", &q), Some((5, " def")));
    p = choice(p, q);
    assert_eq!(run_parser_impl("abc def", &p), Some((5, " def")));
}
{% endhighlight %}
And got a lovely message:
{% highlight rust %}
p = fmap(|x: (i32, ())| x.0, seq(p, fail_parser()));
                             ^^^^^^^^^^^^^^^^^^^^^ expected opaque type, found a different opaque type
{% endhighlight %}

Right, so there's a problem with opaque types. At line 3 `p` gets assigned some type from `fmap`. And then
at line 5 we're trying to assign a value of a different opaque type into `p`. This is obviously wrong.

The natural thing to do here is to store parser in a heap and make `p` point to it. We then would do just that
on line 3, on line 5 and 9 we would create a new parser, put it in an another place in a heap and make `p`
point to it instead. I tried to do just that, but probably made some mistake as it didn't work out.

Since I was tired, the solution that I finally arrived at is rather heavy handed:
[everything is a Box](https://github.com/projedi/lua-in-rust/commit/b9bb4226901a06e250e918fe32843909ddf01bb3).
All it does is changes `impl Parser<'a, T>` to `Box<dyn Parser<'a, T>`. Which puts **every** parser in a heap.
It also added new lifetime requirement:
{% highlight rust %}
fn satisfies<'a, 'b>(f: impl Fn(char) -> bool + 'b) -> Box<dyn Parser<'a, char> + 'b> {
    Box::new(move |s: ParserState<'a>| {
        let c = s.input[s.index..].chars().next()?;
        if f(c) {
            let mut out_s = s;
            out_s.index += 1;
            return Some((c, out_s));
        }
        None
    })
}
{% endhighlight %}
`f` is now moved into a `Box` and so we need guarantees that `f` lives at least as long as `Parser` inside
the returned box.

The downside of the approach - every parser allocates a place in a heap. It's suboptimal, I'd look at this
again when time comes for performance optimisations.

parser_lib again
================

And now just a bit more utility parsers to make `parser_lib` ready to work on Lua. [Code](https://github.com/projedi/lua-in-rust/commit/047042b24ef0bebc2a95075ca7c98702aa5638ae)

* `seq_bind(p, f)` runs parser `p`, extracts the result `x` and returns parser `f(x)`.
* `seq1(p1, p2)`, `seq2(p1, p2)`, `seq_(p1, p2)` that extract only the first result (`seq1`), the second result (`seq2`) or ignore the results completely (`seq_`)
* `seqs_[p1, p2, ...]` that's implemented as a declarative macro and looks like a standard `vec!` macro. It just applies `seq_` repeatedly (and now remember that every time a new heap allocation is made... Ouch.).
* `choices_(ps)` that accepts a vector of parsers and chooses the first that passes. It also just applies `choice` in a loop. The reason that `seqs_` couldn't use a vector and this could - `seq_` doesn't care what return types `p1, p2, ...` have, while `choices_` requires that all parsers return the same type.
* `try_parser(p)` tries to run parser `p` and if it returns `x`, returns `Some(x)` and if it fails, returns `None` without consuming input.
* `not_parser(p)` that tries to run parser `p` and if it succeeds, fails, and if it fails, returns `()` without consuming input.
