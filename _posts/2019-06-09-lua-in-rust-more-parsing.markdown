---
layout: post
title: "Lua in Rust: More parsing"
categories: "lua-in-rust"
---

Going back to `parser_lib` to move beyond lexing.

Parse from something other than a string
========================================

The initial `parser_lib` implementation hardcodes input as `&str`, but it's not a necessary restriction:
all you need from input is the ability to consequently select items from it. This is precisely what iterators
do, so instead of
{% highlight rust %}
#[derive(Copy, Clone)]
struct ParserState<'a> {
    input: &'a str,
    index: usize,
  }
{% endhighlight %}
we now have
{% highlight rust %}
#[derive(Clone)]
struct ParserState<I> {
    iterator: I,
    consumed_count: usize,
}
{% endhighlight %}
So, instead of an immutable `input`, which points to the entire input string (a change I made [here]({% post_url 2019-06-03-lua-in-rust-combinatory-parsing-cont %})) I now need to go back to a mutable thing pointing directly at the next symbol to parse. `consumed_count` is essentially the same as `index`, but with a more suggestive (I hope) name.
Also, I removed a `Copy` trait because it's too restrictive on types of iterators allowed.

Now, the code, that needed to change significantly:
{% highlight rust %}
fn satisfies<'a, T, I: Iterator<Item = T>>(
    f: impl Fn(&T) -> bool + 'a,
) -> Box<dyn Parser<I, T> + 'a> {
    Box::new(move |s: ParserState<I>| {
        let mut out_s = s;
        let c = out_s.iterator.next()?;
        out_s.consumed_count += 1;
        if f(&c) {
            Some((c, out_s))
        } else {
            None
        }
    })
}
{% endhighlight %}
`f` instead of taking `char` by value now takes reference to `T`.

{% highlight rust %}
fn parsed_string<'a, 'b: 'a, T: 'a>(
    p: Box<dyn Parser<std::str::Chars<'b>, T> + 'a>,
) -> Box<dyn Parser<std::str::Chars<'b>, (T, &'b str)> + 'a> {
    Box::new(move |s| {
        let (p_result, p_s) = p(s.clone())?;
        Some((
            (
                p_result,
                &s.iterator.as_str()[0..p_s.consumed_count - s.consumed_count],
            ),
            p_s,
        ))
    })
}
{% endhighlight %}
This parser was a reason for switching to an immutable `input`. So, now it does the following:
run `p` with a clone of state `s`, obtaining new `p_s`; then take an iterator from unmodified `s`
and extract a string from it of length `p_s.consumed_count - s.consumed_count` and return it together
with state `p_s` and the actual result `p_result` of `p`.

{% highlight rust %}
fn sequence_parser<'a, T: PartialEq, S: Iterator<Item = T>,
    I: Iterator<Item = T>>(
    expected_sequence: impl Fn() -> S + 'a,
) -> Box<dyn Parser<I, ()> + 'a> {
    Box::new(move |mut s| {
        let mut expected_iter = expected_sequence();
        loop {
            match expected_iter.next() {
                Some(expected_t) => {
                    let actual_t = s.iterator.next()?;
                    s.consumed_count += 1;
                    if expected_t != actual_t {
                        return None;
                    }
                }
                None => {
                    return Some(((), s));
                }
            }
        }
    })
}

fn string_parser<'a, 'b: 'a>(
    expected_str: &'a str,
) -> Box<dyn Parser<std::str::Chars<'b>, &'b str> + 'a> {
    fmap(
        |(_, s)| s,
        parsed_string(sequence_parser(move || expected_str.chars())),
    )
}
{% endhighlight %}
`string_parser` needs a generalisation to work with any iterator. I settled on `sequence_parser` that
takes an `expected_sequence` that produces an expected iterator. `sequence_parser` then iterates over
input iterator and expected iterator simultaneously until either expected iterator yields nothing (which
is a successfull parse), input iterator yields nothing (that's a parse failure) or they yield different items
(this also is a parse failure). `string_parser` can then be easily defined as a composition of `parsed_string`
and `sequence_parser`.

{% highlight rust %}
fn eof<'a, I: Iterator + 'a>() -> Box<dyn Parser<I, ()> + 'a> {
    Box::new(move |mut s| match s.iterator.next() {
        None => Some(((), s)),
        Some(_) => None,
    })
}
{% endhighlight %}
`eof` now needs to check if `iterator` can yield something. If it can't then the parse is successful.

Other than that, users needed to change types from `Parser<'a, T>` to `Parser<I, T>`, in `run_parser` instead of passing in `&str` you pass an iterator (or switch to `run_string_parser` that does it itself).

All of this can be seen in [this commit](https://github.com/projedi/lua-in-rust/pull/2/commits/aed904f1d823be0dcf29f0f553f8be68e3d9aa41).
