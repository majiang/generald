/** This module implements a variety of classes derived from Function. */
module generald.functions;

import std.typecons, std.traits;

alias Maybe = Nullable;

/// A class representing a function.
abstract class Function(A, B)
{
	abstract B opCall(A);
	alias InputType = A;
	alias OutputType = B;
}

/// Template for converting a function to Function instance.
class RealFunction(alias f, A=ParameterTypeTuple!f[0], B=ReturnType!f) : Function!(A, B)
{
	pragma(msg, "RealFunction(", A.stringof, " -> ", ParameterTypeTuple!f[0].stringof, " -> ", ReturnType!f.stringof, " -> ", B.stringof, ")");
	override ReturnType!f opCall(ParameterTypeTuple!f[0] x)
	{
		return f(x);
	}
	mixin Singleton;
}

///
class IdentityFunction(T) : Function!(T, T)
{
	override T opCall(T x)
	{
		return x;
	}
	mixin Singleton;
}

///
unittest
{
	auto f = RealFunction!(id!int).get;
	assert (f(0) == 0);
}

/// Compose two Functions.
class ComposedFunction(A, B, C, D) : Function!(A, D)
	if (is (B : C))
{
	Function!(A, B) f;
	Function!(C, D) g;
	this (Function!(A, B) f, Function!(C, D) g)
	{
		this.f = f;
		this.g = g;
	}
	override D opCall(A x)
	{
		return g(f(x));
	}
}

/// ditto
auto compose(F, G)(F f, G g)
	if (is (F : Function!(F.InputType, F.OutputType)) &&
		is (G : Function!(G.InputType, G.OutputType)) &&
		is (F.OutputType : G.InputType))
{
	return new ComposedFunction!(F.InputType, F.OutputType, G.InputType, G.OutputType)(f, g);
}

unittest
{
	auto f = RealFunction!(triple!int).get.compose(RealFunction!(increment!int).get);
	auto g = RealFunction!(increment!int).get.compose(RealFunction!(triple!int).get);
	assert (f(0) == 1);
	assert (f(1) == 4);
	assert (g(0) == 3);
	assert (g(1) == 6);
}

/// Return function for Maybe.
class MaybeReturn(A) : Function!(A, Maybe!A)
{
	override Maybe!A opCall(A x)
	{
		return Maybe!A(x);
	}
	mixin Singleton;
}

/// Bind function for Maybe: (a -> Maybe b) -> (Maybe a -> Maybe b).
class MaybeBind(A, B) : Function!(Maybe!A, Maybe!B)
{
	Function!(A, Maybe!B) f;
	this (Function!(A, Maybe!B) f)
	{
		this.f = f;
	}
	override Maybe!B opCall(Maybe!A x)
	{
		if (x.isNull)
			return Maybe!B();
		return f(x.get);
	}
}

/// ditto
auto maybeBind(F)(F f)
{
	static if (is (F.OutputType : Maybe!B, B))
		return new MaybeBind!(F.InputType, B)(f);
	else static assert (false);
}

/// fmap function for Maybe.
auto maybeMap(F)(F f)
	if (is (F : Function!(A, B), A, B))
{
	return f.compose(MaybeReturn!(F.OutputType).get).maybeBind;
}

///
unittest
{
	auto maybeId = maybeMap(RealFunction!(id!int).get);
	assert (maybeId(Maybe!int(0)) == Maybe!int(0));
}

/// Compose two Functions f and g where f emits a Maybe!B and g takes a B.
auto maybeCompose(F, G)(F f, G g)
{
	return f.compose(g.maybeBind);
}

///
unittest
{
	auto c = RealFunction!(collatz!int).get;
	auto lc = c.maybeCompose(c).maybeCompose(c);
	auto rc = c.maybeCompose(c.maybeCompose(c));
	foreach (i; 0..10)
		assert (lc(i).maybeEqual(rc(i)));
}

/// Function from Maybe to void can be constructed from a Function to void.
class MaybeSink(A) : Function!(Maybe!A, void)
{
	Function!(A, void) sink;
	this (Function!(A, void) sink)
	{
		this.sink = sink;
	}
	override void opCall(Maybe!A x)
	{
		if (x.isNull)
			return;
		sink(x);
	}
}

/// ditto
auto maybeSink(S)(S sink)
	if (is (S : Function!(A, void), A))
{
	return new MaybeSink!(S.InputType)(sink);
}

/// Maybe do something, and return null.
class MaybeNothing(A, B, C=void) : Function!(A, Maybe!B)
{
	Function!(A, C) sink;
	this (Function!(A, C) sink)
	{
		this.sink = sink;
	}
	override Maybe!B opCall(A x)
	{
		sink(x);
		return Maybe!B();
	}
}

/// ditto
auto maybeNothing(B, F)(F f)
{
	return new MaybeNothing!(F.InputType, B, F.OutputType)(f);
}

/// Either type.
struct Either(A, B)
	if (!is (A : B) && !is (B : A))
{
	this (A a)
	{
		this.nonNull = true;
		this.which = false;
		this._a = a;
	}
	this (B b)
	{
		this.nonNull = true;
		this.which = true;
		this._b = b;
	}
	typeof (this) opAssign(A a)
	{
		this.nonNull = true;
		this.which = false;
		this._a = a;
		return this;
	}
	typeof (this) opAssign(B b)
	{
		this.nonNull = true;
		this.which = true;
		this._b = b;
		return this;
	}
	string toString()
	{
		import std.conv;
		if (which)
			return _b.to!string;
		else
			return _a.to!string;
	}
private:
	bool nonNull, which;
	A _a;
	B _b;
	@property A a()
	in
	{
		assert (this.nonNull);
		assert (!this.which);
	}
	body
	{
		return _a;
	}
	@property B b()
	in
	{
		assert (this.nonNull);
		assert ( this.which);
	}
	body
	{
		return _b;
	}
}

/// Function from either.
class EitherFunction(A, B, C) : Function!(Either!(A, B), C)
{
	Function!(A, C) f;
	Function!(B, C) g;
	this (Function!(A, C) f, Function!(B, C) g)
	{
		this.f = f;
		this.g = g;
	}
	override C opCall(Either!(A, B) x)
	{
		if (!x.which)
			return f(x.a);
		if ( x.which)
			return g(x.b);
		assert (false);
	}
}

/// ditto
auto eitherFunction(F, G)(F f, G g)
	if (is (F.OutputType == G.OutputType))
{
	return new EitherFunction!(F.InputType, G.InputType, F.OutputType)(f, g);
}

/// Function to Either.
alias LeftEither(A, B) = RealFunction!(left!(B, A));
version (none)
class LeftEither(A, B) : Function!(A, Either!(A, B))
{
	override OutputType opCall(InputType x)
	{
		return OutputType(x);
	}
	mixin Singleton;
}

/// ditto
alias RightEither(A, B) = RealFunction!(right!(A, B));
version (none)
class RightEither(A, B) : Function!(B, Either!(A, B))
{
	override OutputType opCall(InputType x)
	{
		return OutputType(x);
	}
	mixin Singleton;
}

/// Either!(, B) functor at A.
Either!(A, B) left(B, A)(A a)
{
	Either!(A, B) x;
	x = a;
	return x;
}

/// Either!(A, ) functor at B.
Either!(A, B) right(A, B)(B b)
{
	Either!(A, B) x;
	x = b;
	return x;
}

/// Function from and to Either.
auto eitherEither(F, G)(F f, G g)
{
	return eitherFunction(
		f.compose(LeftEither!(F.OutputType, G.OutputType).get),
		g.compose(RightEither!(F.OutputType, G.OutputType).get));
}

/// Function to Tuple.
class FunctionTuple(A, B, C) : Function!(A, Tuple!(B, C))
{
	Function!(A, B) f;
	Function!(A, C) g;
	this (Function!(A, B) f, Function!(A, C) g)
	{
		this.f = f;
		this.g = g;
	}
	override Tuple!(B, C) opCall(A x)
	{
		return tuple(f(x), g(x));
	}
}

/// ditto
auto functionTuple(F, G)(F f, G g)
	if (is (F.InputType == G.InputType))
{
	return new FunctionTuple!(F.InputType, F.OutputType, G.OutputType)(f, g);
}

/// Function from Tuple.
class TupleLeft(A, B) : Function!(Tuple!(A, B), A)
{
	override A opCall(Tuple!(A, B) x)
	{
		return x[0];
	}
	mixin Singleton;
}

/// ditto
class TupleRight(A, B) : Function!(Tuple!(A, B), B)
{
	override B opCall(Tuple!(A, B) x)
	{
		return x[1];
	}
	mixin Singleton;
}

/// Function from and to Tuple.
auto tupleTuple(F, G)(F f, G g)
{
	return functionTuple(
		TupleLeft!(F.InputType, G.InputType).get.compose(f),
		TupleRight!(F.InputType, G.InputType).get.compose(g));
}

/// Singleton pattern.
mixin template Singleton(Flag!"hideConstructor" hideConstructor = Yes.hideConstructor)
{
	static typeof (this) get()
	{
		static typeof (this) instance;
		if (instance is null)
			return instance = new typeof (this)();
		return instance;
	}
	static if (hideConstructor)
	private this ()
	{
	}
}

version (unittest)
{
	T id(T)(T x)
	{
		return x;
	}
	T triple(T)(T x)
	{
		return x * 3;
	}
	T increment(T)(T x)
	{
		return x + 1;
	}
	Maybe!T collatz(T)(T x)
	{
		if (x <= 1)
			return Maybe!T();
		if (x & 1)
			return Maybe!T(x.triple.increment);
		return Maybe!T(x / 2);
	}
	bool maybeEqual(T)(Maybe!T x, Maybe!T y)
	{
		if (x.isNull || y.isNull)
			return x.isNull && y.isNull;
		return x.get == y.get;
	}
}

unittest
{
	import std.stdio;
	stderr.writeln("unittest passed!");
}