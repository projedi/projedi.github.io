---
layout: lua-in-rust
title: "Lua in Rust: Left recursion"
categories: "lua-in-rust"
---

It's time to learn how to parse expressions with binary operators.

Expressions with binary operators
=================================

Let's try to parse arithmetic expressions that contain integer numbers, binary
operators `+` `-` `*` `^` and one unary operator `-`. Usual precedence and
associativity rules apply: `+`, `-` (binary) are least binding, then follows `*`, then `-` (unary) and finally `^`.
`^` is right associative, others are left associative. This means, that the expression
{% highlight rust %}
0 - 1 + 2 * -3^4^5
{% endhighlight %}
should be viewed as
{% highlight rust %}
((0 - 1) + (2 * (-(3^(4^5)))))
{% endhighlight %}

Defining datatypes:
{% highlight rust %}
enum BinOp {
    Add,
    Sub,
    Mul,
    Pow,
}

enum UnOp {
    Neg,
}

enum Exp {
    Num(f64),
    BinOp(Box<Exp>, BinOp, Box<Exp>),
    UnOp(UnOp, Box<Exp>),
}
{% endhighlight %}

And then defining a parser that we want to write:

{% highlight rust %}
fn num_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, f64> + 'a> {
    seq_bind(
        parsed_string(many1(satisfies(|c: &char| c.is_ascii_digit()))),
        |(_, num_str)| match num_str.parse::<f64>() {
            Ok(num) => fmap(move |_| num, empty_parser()),
            Err(_) => fail_parser(),
        },
    )
}

fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![
        fmap(
            |(lhs, (op, rhs))| Exp::BinOp(Box::new(lhs), op, Box::new(rhs)),
            seq(allow_recursion(exp_parser),
                seq(binop_parser(), allow_recursion(exp_parser)))),
        fmap(
            |(op, e)| Exp::UnOp(op, Box::new(e)),
            seq(unop_parser(), allow_recursion(exp_parser))),
        fmap(Exp::Num, num_parser()),
    ])
}
{% endhighlight %}

This, of course, does not work. First of all, we say nothing about precedence or associativity,
so this code has no chance of doing the right thing. Second of all: `choices` will try to parse
a binary expression by `fmap(..., seq(allow_recursion(exp_parser), ...))`, so the first thing
it'll do (without consuming any input) is recursively call `exp_parser`, which will, again,
recursively call `exp_parser` with exactly the same state, so this is an infinite recursion.
This last problem is known as the left recursion. Fortunately, there's a way to get rid of it.

Transforming parser to eliminate left recursion
===============================================

#### Right associative binary operator

Let's first look at a more simple grammar:
{% highlight rust %}
enum Exp {
    Num(f64),
    Pow(Box<Exp>, Box<Exp>),
}
{% endhighlight %}
It contains only numbers and right-associative `^` operator. Typical expressions are:
`1`, `1^2`, `1^2^3`, `1^2^3^4` which should be read as `1`, `1^2`, `1^(2^3)`, `1^(2^(3^4))`.
Now, looking closely, we see, that on the left side of `^` is always an `Exp::Num`, it's
never an `Exp::Pow`. Therefore, we can write our parser as such:
{% highlight rust %}
fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![
        fmap(
            |(lhs, rhs)| Exp::Pow(Box::new(Exp::Num(lhs)), Box::new(rhs)),
            seq(num_parser(),
                seq2(char_parser('^'), allow_recursion(exp_parser)))),
        fmap(Exp::Num, num_parser()),
    ])
}
{% endhighlight %}
On the left side of `^` we parse with `num_parser`, instead of `allow_recursion(exp_parser)`, therefore
eliminating left recursion.

Okay, what if there're two right associative operators of the same precedence. Say, `,` and `;`. Again,
let's look at concrete expressions: `1,2;3` and `1;2,3`, which are read as `1,(2;3)` and `1;(2,3)`. So,
nothing really changed. We can write parser as:
{% highlight rust %}
fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![
        fmap(
            |(lhs, rhs)| Exp::Comma(Box::new(Exp::Num(lhs)), Box::new(rhs)),
            seq(num_parser(),
                seq2(char_parser(','), allow_recursion(exp_parser)))),
        fmap(
            |(lhs, rhs)| Exp::Semi(Box::new(Exp::Num(lhs)), Box::new(rhs)),
            seq(num_parser(),
                seq2(char_parser(';'), allow_recursion(exp_parser)))),
        fmap(Exp::Num, num_parser()),
    ])
}
{% endhighlight %}
This parser first tries number followed by `,`, if it doesn't work, tries number followed by `;` and
finally just settles on a number.

#### Left associative binary operator

Now, replacing right associative `^` with left associative `+`.
{% highlight rust %}
enum Exp {
    Num(f64),
    Sum(Box<Exp>, Box<Exp>),
}
{% endhighlight %}
Expressions are: `1`, `1+2`, `1+2+3`, `1+2+3+4` which are read `1`, `1+2`, `(1+2)+3`,`((1+2)+3)+4`.
This time, there's always an `Exp::Num` on the right side of `+`. And this is not all: our expressions
also start with an `Exp::Num`. So, to parse that we need to consume a number, then try to parse `+`
followed by a number, put both into a `Exp::Sum`, then again parse `+` followed by a number and put
`Exp::Sum` from a previous iteration and the number from this iteration into a new `Exp::Sum` and repeat the process.
{% highlight rust %}
fn exp_parser_helper<'a, 'b: 'a>(lhs: Exp) -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(
        try_parser(seq2(char_parser('+'), num_parser())),
        move |rhs| {
            let lhs = lhs.clone();
            match rhs {
                Some(rhs) => exp_parser_helper(Exp::Sum(Box::new(lhs), Box::new(Exp::Num(rhs)))),
                None => fmap(move |_| lhs.clone(), empty_parser()),
            }
        },
    )
}

fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(fmap(Exp::Num, num_parser()), exp_parser_helper)
}
{% endhighlight %}

Again, if we look at two left associative operators of the same precedence (say, `+` and `-`),
nothing of significance is changed: `1+2-3` is read as `(1+2)-3` and `1-2+3` is read as `(1-2)+3`.
So, when parsing we need to look for `+` followed by a number or for `-` followed by a number:
{% highlight rust %}
fn exp_parser_helper<'a, 'b: 'a>(lhs: Exp) -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(
        try_parser(seq2(char_parser('+'), num_parser())),
        move |rhs| {
            let lhs = lhs.clone();
            match rhs {
                Some(rhs) => exp_parser_helper(Exp::Sum(Box::new(lhs), Box::new(Exp::Num(rhs)))),
                None =>
                    seq_bind(
                        try_parser(seq2(char_parser('-'), num_parser())),
                        move |rhs| {
                        let lhs = lhs.clone();
                        match rhs {
                            Some(rhs) => exp_parser_helper(Exp::Sub(Box::new(lhs), Box::new(Exp::Num(rhs)))),
                            None => fmap(move |_| lhs.clone(), empty_parser()),
                        }}),
            }
        },
    )
}

fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(fmap(Exp::Num, num_parser()), exp_parser_helper)
}
{% endhighlight %}

(Now, that I'm writing this note, it's clear that this `exp_parser_helper` could have been written way more simply)

Unfortunately, this implementation imposed a restriction on `Exp`: it now must implement `Clone` trait. This is because
we capture `Exp` inside a parser which really is an `Fn` closure that can be called multiple times, and if we need
to move from `Exp` during first call, there's nothing to move from the second time it's called. To avoid that, we move
from clone objects.

#### Combining operators of different precedences

Let's look at the grammar:
{% highlight rust %}
enum Exp {
    Num(f64),
    Sum(Box<Exp>, Box<Exp>),
    Mul(Box<Exp>, Box<Exp>),
}
{% endhighlight %}
And again, concrete expressions:
1. `1+2+3*4` ⇒ `(1+2)+(3*4)`
1. `1+2*3+4` ⇒ `(1+(2*3))+4`
1. `1*2+3+4` ⇒ `((1*2)+3)+4`
1. `1*2*3+4` ⇒ `((1*2)*3)+4`
1. `1*2+3*4` ⇒ `(1*2)+(3*4)`
1. `1+2*3*4` ⇒ `1+((2*3)*4)`

What we can see is that arguments of `Exp::Mul` are either `Exp::Num` or `Exp::Mul` and never are `Exp::Sum`.
So, when parsing `Exp::Mul` we never need to try `Exp::Sum` case. And for `Exp::Sum` there's now no difference
between `Exp::Num` and `Exp::Mul`: (recursively) replacing `x*y` with `x` in examples above gives us:
1. `1+2+3` ⇒ `(1+2)+3`
1. `1+2+4` ⇒ `(1+2)+4`
1. `1+3+4` ⇒ `(1+3)+4`
1. `1+4` ⇒ `1+4`
1. `1+3` ⇒ `1+3`
1. `1+2` ⇒ `1+2`

These are still valid readings.

Therefore, to parse expression we use a layered approach. Order operators in increasing precedence and then:
1. Parse first operators, whose arguments are from the layer 2 (instead of `Exp::Num`).
1. Parse second operators, whose arguments are from the layer 3.
1. ...
1. Parse last operators, whose arguments are `Exp::Num`.

{% highlight rust %}
fn exp0_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    fmap(Exp::Num, num_parser())
}

fn exp1_parser_helper<'a, 'b: 'a>(lhs: Exp) -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(
        try_parser(seq2(char_parser('*'), exp0_parser())),
        move |rhs| {
            let lhs = lhs.clone();
            match rhs {
                Some(rhs) => exp_parser_helper(Exp::Mul(Box::new(lhs), Box::new(Exp::Num(rhs)))),
                None => fmap(move |_| lhs.clone(), empty_parser()),
            }
        },
    )
}

fn exp1_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(exp0_parser(), exp1_parser_helper)
}

fn exp2_parser_helper<'a, 'b: 'a>(lhs: Exp) -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(
        try_parser(seq2(char_parser('+'), exp1_parser())),
        move |rhs| {
            let lhs = lhs.clone();
            match rhs {
                Some(rhs) => exp_parser_helper(Exp::Sum(Box::new(lhs), Box::new(Exp::Num(rhs)))),
                None => fmap(move |_| lhs.clone(), empty_parser()),
            }
        },
    )
}

fn exp2_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(exp1_parser(), exp2_parser_helper)
}

fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    exp2_parser()
}
{% endhighlight %}

Mixing in right associative operators works just as fine.

#### Adding unary operators

Let's look at unary `-` with less binding `+` and with more binding `^`:
1. `-1+2` ⇒ `(-1)+2`
1. `-1^2` ⇒ `-(1^2)`

This fits into layered approach:
* arguments of `+` are more binding than `+`
* an argument of `-` is more binding than `-`
* arguments of `^` are `Exp::Num`

There's, however, a weird case:
1. `1+-2` ⇒ `1+(-2)`
1. `1^-2` ⇒ `1^(-2)`

The first one is fine(-ish). But in the second case right hand side contains a `-`,
that's less binding than `^`. I wanted to forbid this at all, but Lua allows it,
so it has to stay.

In this specific example it can be easily solved: allow right hand side of `^` to
start with unary negation.

#### The complete picture

{% highlight rust %}
enum BinOp {
    Add,
    Sub,
    Mul,
    Pow,
    Comma,
    Semi,
}

enum UnOp {
    Neg,
}

enum Exp {
    Num(f64),
    BinOp(Box<Exp>, BinOp, Box<Exp>),
    UnOp(UnOp, Box<Exp>),
}

fn num_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, f64> + 'a> {
    seq_bind(
        parsed_string(many1(satisfies(|c: &char| c.is_ascii_digit()))),
        |(_, num_str)| match num_str.parse::<f64>() {
            Ok(num) => fmap(move |_| num, empty_parser()),
            Err(_) => fail_parser(),
        },
    )
}

fn exp0_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![fmap(Exp::Num, num_parser())])
}

fn exp1_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![
        fmap(
            move |(lhs, rhs)| Exp::BinOp(Box::new(lhs), BinOp::Pow, Box::new(rhs)),
            seq(
                exp0_parser(),
                seq2(char_parser('^'), allow_recursion(exp2_parser)),
            ),
        ),
        exp0_parser(),
    ])
}

fn exp2_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![
        fmap(
            |e| Exp::UnOp(UnOp::Neg, Box::new(e)),
            seq2(char_parser('-'), allow_recursion(exp2_parser)),
        ),
        exp1_parser(),
    ])
}

fn mul_parser<'a, 'b: 'a>(lhs: Exp) -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(
        try_parser(seq2(char_parser('*'), exp2_parser())),
        move |rhs| {
            let lhs = lhs.clone();
            match rhs {
                Some(rhs) => mul_parser(Exp::BinOp(Box::new(lhs), BinOp::Mul, Box::new(rhs))),
                None => fmap(move |_| lhs.clone(), empty_parser()),
            }
        },
    )
}

fn exp3_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(exp2_parser(), mul_parser)
}

fn addsub_parser<'a, 'b: 'a>(lhs: Exp) -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(
        try_parser(seq2(char_parser('+'), exp3_parser())),
        move |rhs| {
            let lhs = lhs.clone();
            match rhs {
                Some(rhs) => {
                    addsub_parser(Exp::BinOp(Box::new(lhs), BinOp::Add, Box::new(rhs)))
                }
                None => seq_bind(
                    try_parser(seq2(char_parser('-'), exp3_parser())),
                    move |rhs| {
                        let lhs = lhs.clone();
                        match rhs {
                            Some(rhs) => addsub_parser(Exp::BinOp(
                                Box::new(lhs),
                                BinOp::Sub,
                                Box::new(rhs),
                            )),
                            None => fmap(move |_| lhs.clone(), empty_parser()),
                        }
                    },
                ),
            }
        },
    )
}

fn exp4_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    seq_bind(exp3_parser(), addsub_parser)
}

fn exp5_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    choices(vec![
        fmap(
            move |(lhs, rhs)| Exp::BinOp(Box::new(lhs), BinOp::Comma, Box::new(rhs)),
            seq(
                exp4_parser(),
                seq2(char_parser(','), allow_recursion(exp5_parser)),
            ),
        ),
        fmap(
            move |(lhs, rhs)| Exp::BinOp(Box::new(lhs), BinOp::Semi, Box::new(rhs)),
            seq(
                exp4_parser(),
                seq2(char_parser(';'), allow_recursion(exp5_parser)),
            ),
        ),
        exp4_parser(),
    ])
}

fn exp_parser<'a, 'b: 'a>() -> Box<dyn Parser<std::str::Chars<'b>, Exp> + 'a> {
    exp5_parser()
}
{% endhighlight %}

Generalization of doom
======================

#### Unary operators on the right hand side

Then I decided to generalize operator parsing and put it into `parser_lib` itself. First
of all, a hack with `^` and unary `-` had to go. So I added yet another unary operator `!`,
that binds least of all. This time all the operators needed to handle it in their right hand side.
So, again, examples:
1. `1^-2^3` ⇒ `1^(-(2^3))`
1. `1^-2+3` ⇒ `(1^(-2))+3`
1. `1+-2^3` ⇒ `1+(-(2^3))`
1. `1+-2+3` ⇒ `(1+(-2))+3`
1. `1^!2^3` ⇒ `1^(!(2^3))`
1. `1^!2+3` ⇒ `(1^(!2))+3`
1. `1+!2^3` ⇒ `1+(!(2^3))`
1. `1+!2+3` ⇒ `(1+(!2))+3`
1. `1+-!2` ⇒ `1+(-(!2))`
1. `1^-!2` ⇒ `1^(-(!2))`

This leads to an idea: right hand side of operator `op` can start with unary operators whose arguments are more binding than `op`.

#### The generalization effort

And it all went downhill from here. The process itself was quite straightforward.
1. Generalize parsing of unary operators on the right hand side of binary operators.
   This involves passing encountered unary operators through the chain of `exp*_parser` and
   trying them out on the right hand side.
1. Generalize unary operators. At each level (which I call line) parser for unary operators need to know new unary operators,
   existing unary operators and what's the next parser in line. Then you parse with new and existing unary operators, add
   new operators to the list and call next parser with those.
1. Generalize right associative binary operators. At each line these need to know new binary operators, existing unary operators,
   and next parser line.
1. Generalize left associative binary operators. These are just like right associative, but implementation was more complicated.
1. Now top level `exp_parser` manually combines all these line parsers. This can be fixed by introducing a table with all the
   operators and their parsers and a helper function that will combine line parsers all by itself.

Now, because of this `next_parser` passing at each line, parser needed to become copyable, because we capture them in closures.
To do that two methods were used:
* Wrap parser closure in reference counting box `std::rc::Rc` instead of `Box`
* Pass around factories (`impl Fn() -> Smth`) instead of things themselves.

The [result](https://github.com/projedi/lua-in-rust/commit/ec03273f91b059d24751d7958f1611791e0efeb7) is an unreadable mess.

Indirect left recursion
=======================

Even though, the expression parsing from above became quite unreadable, it's still usable. Now, for something unusable.
Let's look at:
{% highlight text %}
Exp ::= ( Exp )
      | Var
      | FunctionCall

Var ::= Name
      | Exp . Name

FunctionCall ::= Exp ( )
{% endhighlight text %}

`Exp`, `Var`, `FunctionCall` are mutually left recursive. How to handle them?
[There's](https://en.wikipedia.org/wiki/Left_recursion) an algorithm.

{% highlight text %}
Exp ::= ( Exp )
      | Var
      | FunctionCall

Var ::= Name Var'
      | ( Exp ) . Name Var'
      | FunctionCall . Name Var'

Var' ::= . Name Var'
       | <>

FunctionCall ::= ( Exp ) ( ) FunctionCall'
               | Name Var' ( ) FunctionCall'
               | ( Exp ) . Name Var' ( ) FunctionCall'

FunctionCall' ::= . Name Var' ( ) FunctionCall'
                | ( ) FunctionCall'
                | <>
{% endhighlight text %}

Duplication saved the day. Except, of course, for maintainability and extensibility.
What if we needed to expand original declaration a bit?
{% highlight text %}
Exp ::= ( Exp )
      | Var
      | FunctionCall

Var ::= Name
      | Exp . Name
      | Exp [ Exp ]

FunctionCall ::= Exp ( )
               | Exp : Name ( )
{% endhighlight text %}

We just added indexing to `Var` and "method call" to `FunctionCall`.

{% highlight text %}
Exp ::= ( Exp )
      | Var
      | FunctionCall

Var ::= Name Var'
      | ( Exp ) . Name Var'
      | FunctionCall . Name Var'
      | ( Exp ) [ Exp ] Var'
      | FunctionCall [ Exp ] Var'

Var' ::= . Name Var'
       | [ Exp ] Var'
       | <>

FunctionCall ::= ( Exp ) ( ) FunctionCall'
               | Name Var' ( ) FunctionCall'
               | ( Exp ) . Name Var' ( ) FunctionCall'
               | ( Exp ) [ Exp ] Var' ( ) FunctionCall'
               | FunctionCall ( ) FunctionCall'
               | ( Exp ) : Name ( ) FunctionCall'
               | Name Var' : Name ( ) FunctionCall'
               | ( Exp ) . Name Var' : Name ( ) FunctionCall'
               | ( Exp ) [ Exp ] Var' : Name ( ) FunctionCall'

FunctionCall' ::= . Name Var' ( ) FunctionCall'
                | [ Exp ] Var' ( ) FunctionCall'
                | ( ) FunctionCall'
                | . Name Var' : Name ( ) FunctionCall'
                | [ Exp ] Var' : Name ( ) FunctionCall'
                | : Name ( ) FunctionCall'
                | <>
{% endhighlight text %}

And while I trusted myself enough to correctly augment `Var` and `Var'`, I didn't
even bother with trying to augment `FunctionCall` and `FunctionCall'` and so ran
the algorithm from scratch.

I don't want to convert Lua grammar to this by hand, so I'll be investigating how
to define parsers such that this transformations are not needed.
