---
layout: post
title: "Heterogeneous equality"
date: 2015-01-02
---

Let's look at the implementation of propositional equality in Agda and in Idris.

Equality in Agda
----------------

This is how Agda defines equality in the
[Relation.Binary.Core](https://github.com/agda/agda-stdlib/blob/v0.9/src/Relation/Binary/Core.agda#L151):
{% highlight agda %}
data _≡_ {a} {A : Set a} (x : A) : A → Set a where
  refl : x ≡ x

{-# BUILTIN EQUALITY _≡_ #-}
{-# BUILTIN REFL refl #-}
{% endhighlight %}

Now let's try to prove a simple property of vectors `xs ++ [] = xs`:
{% highlight agda %}
module Agda1 where

open import Data.Vec
open import Relation.Binary.Core

lemma-[]-right-++-identity : ∀ {A n} (xs : Vec A n) → xs ++ [] ≡ xs
lemma-[]-right-++-identity = ?
{% endhighlight %}
And we immediatly fail with an error:
{% highlight agda %}
n != n .Data.Nat.+ 0 of type .Data.Nat.ℕ
when checking that the expression xs has type
Vec A (n .Data.Nat.+ 0)
{% endhighlight %}
The reason for it is simple: `xs ++ []` has type `Vec A (n + 0)` while
`xs` has type `Vec A n` and since `n + 0` does not reduce to `n` typechecker
has no idea that these two types are identical.  There does not seem to be a
way to introduce a proof of `n + 0 ≡ n` into the typechecker here.

Equality in Idris
-----------------

Let's look how Idris handles this problem. Here's a definition (I am lying, it is
actually hardcoded in the compiler
[here](https://github.com/idris-lang/Idris-dev/blob/v0.9.15.1/src/Idris/AbsSyntaxTree.hs#L1098)):
{% highlight idris %}
data (=) : (x : a) -> (y : b) -> Type where
  Refl : x = x
{% endhighlight %}
Notice that two arguments of `(=)` are of different types! This is because Idris has
**heterogeneous** equality instead of **homogeneous** like Agda. Actually it is somewhat mixed:
Idris will try to use homogeneous version first (i.e. when `b = a`) and if it fails to typecheck
will fall back to the heterogeneous one. I do not know why it does that.

We can now write this:
{% highlight idris %}
module Idris1

lemma_nil_right_concat_identity : (xs : Vect n a) -> xs ++ [] = xs
lemma_nil_right_concat_identity [] = Refl
lemma_nil_right_concat_identity (x :: xs) = cons_cong (lemma_nil_right_concat_identity xs)
 where cons_cong :  {x : a} -> {xs : Vect n a} -> {ys : Vect m a}
                 -> (xs = ys) -> (x :: xs = x :: ys)
       cons_cong Refl = Refl

{% endhighlight %}
A thing to note is that we had to write a helper `cons_cong` instead of using `cong`.

Let's look at `(::)` in `cons_cong`. The one on the left has type
`a -> Vect (n + 0) a -> Vect (S (n + 0)) a` while the one on the right `a -> Vect n a -> Vect (S n) a`.
So these are two *different* `(::)`.
Now consider the type of `cong` defined in
[Prelude.Basics](https://github.com/idris-lang/Idris-dev/blob/v0.9.15.1/libs/prelude/Prelude/Basics.idr#L46):
{% highlight idris %}
cong : {f : t -> u} -> (a = b) -> f a = f b
{% endhighlight %}
`f` on the left is exactly `f` on the right. And this is why we cannot use `cong` in our situation.

Special equality for `Vec` in Agda
----------------------------------

To actually express propositional equality on vectors Agda has a special operator `_≈_` in
[Data.Vec.Equality](https://github.com/agda/agda-stdlib/blob/v0.9/src/Data/Vec/Equality.agda#L24):
{% highlight agda %}
data _≈_ : ∀ {n¹} → Vec A n¹ →
           ∀ {n²} → Vec A n² → Set (s₁ ⊔ s₂) where
  []-cong  : [] ≈ []
  _∷-cong_ : ∀ {x¹ n¹} {xs¹ : Vec A n¹}
               {x² n²} {xs² : Vec A n²}
               (x¹≈x² : x¹ ≊ x²) (xs¹≈xs² : xs¹ ≈ xs²) →
               x¹ ∷ xs¹ ≈ x² ∷ xs²
{% endhighlight %}
Using it we can write our lemma as follows:
{% highlight agda %}
module Agda2 where

open import Data.Vec
open import Data.Vec.Equality
open import Relation.Binary.Core

open PropositionalEquality

lemma-[]-right-++-identity : ∀ {l n} {A : Set l} (xs : Vec A n) → xs ++ [] ≈ xs
lemma-[]-right-++-identity [] = []-cong
lemma-[]-right-++-identity (x ∷ xs) = _≡_.refl ∷-cong (lemma-[]-right-++-identity xs)
{% endhighlight %}
