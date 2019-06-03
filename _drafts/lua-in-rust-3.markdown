---
layout: post
title: "Lua in Rust: Lua lexemes"
categories: "lua-in-rust"
---

Now that `parser_lib` is ready, it's time to actually use it to parse Lua.

Lua lexemes
===========

I usually parse from a string directly into a syntax tree. But this time I'll do something different for a change:
I'll first parse a string into a vector of tokens.

Following [Lua Lexical Conventions](http://www.lua.org/manual/5.1/manual.html#2.1) I defined lua lexemes
[here](https://github.com/projedi/lua-in-rust/commit/7300733e4baced3498779d720c8a7e8919e507dd).

Everything is pretty straightforward apart from `Keyword` and `OtherToken` definitions. Probably the simplest way
of parsing them is enumerating all of them and trying one after the other. So, I need a way to enumerate all the
elements of an enum and also convert them into string. To do that I resorted to a declarative macro.

My macro that matches pattern `$p:vis $n:ident { $($v:ident => $s:literal),* $(,)?}`. First is a visibility modifier
that'll be bound to `$p`, next is an identifier bound to `$n`, then `{`, then a (possibly empty) list of comma separated
pairs, that are optionally terminated by a comma and finally a `}`. A list of pairs are of the form identifier `$v` followed
by `=>` and then literal `$s`. What I wanted to express by all this is: this is an enum with visibility `$p` named `$n` and
with items `$v` that map to strings `$s`. There's a bunch of code generated from this macro:
* Generate the enum itself.
{% highlight rust %}
$p enum $n {
    $($v),*
}
{% endhighlight %}
* Count items. A hacky way: for each item `$v` generate a pair `($v, 1)`, extract the second item (i.e. `1`)
and sum all of them. Note, that function is mark `const` so it should (must?) be evaluated at compile time, producing
an actual constant instead of a giant `1 + 1 + ... + 0` expression.
{% highlight rust %}
pub const fn items_count() -> usize {
    $(($n::$v, 1).1 + )* 0
}
{% endhighlight %}
* Enumerate all the items.
{% highlight rust %}
pub const ITEMS: [$n; $n::items_count()] = [
    $($n::$v),*
];
{% endhighlight %}
* Convert items to string.
{% highlight rust %}
pub fn to_str(&self) -> &'static str {
    match self {
      $($n::$v => $s),*
    }
}
{% endhighlight %}

Now, that I look back at it, I think it's an overkill. What I really need is to enumerate all items, everything
else can very well be done outside a macro.

Parsing Lua
===========

And so [here](https://github.com/projedi/lua-in-rust/commit/cd08246a81ab5e1935393b8ab773540c7f6b6aeb)'s a lexer for Lua.

* `keyword_lexer`.
{% highlight rust %}
fn keyword_lexer<'a, 'b: 'a>(
) -> Box<dyn parser_lib::Parser<'b, lua_syntax::Keyword> + 'a> {
    parser_lib::choices(
        lua_syntax::Keyword::create_sorted_items()
            .iter()
            .map(|item| {
                let i = *item;
                parser_lib::fmap(move |_| i,
                                 parser_lib::string_parser(item.to_str()))
            })
            .collect(),
    )
}
{% endhighlight %}
  Pretty straightforward parsing: we iterate over all keywords and pick the first that matches. There's one problem
  though: we have keywords `else` and `elseif` and if you match against `else` first, it'll succeed. To tackle it
  I first sort (`create_sorted_items`) all the keywords by length (the longest first). This way `elseif` will be
  tried before `else` is.
* `other_token_lexer` is implemented similarly.
* `string_literal_lexer`. Borderline unreadable beast, though simple in essence.
* `long_brackets_lexer`. This one is rather simple: parse the opening long bracket and then parse everything until you reach the closing long bracket.
