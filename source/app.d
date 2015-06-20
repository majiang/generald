import std.stdio;
import generald.functions;

import std.typecons;

class Printer(T) : Function!(T, void)
{
	override void opCall(T x)
	{
		import std.stdio;
		writeln(x);
	}
}

class ArrayPrinter(T) : Function!(T[], void)
{
	override void opCall(T[] x)
	{
		import std.stdio;
		writefln("%(%s\n%)", x);
	}
}

class ScoreParser : Function!(string, Either!(IndividualResult, EOF))
{
	override OutputType opCall(string line)
	{
		import std.string, std.array, std.conv;
		auto buf = line.strip.split("\t");
		if (buf.length == 2)
			return OutputType(IndividualResult(buf[0], buf[1].to!int));
		return OutputType(EOF());
	}
}

alias IndividualResult = Tuple!(string, "player", int, "result");

struct EOF{}

class GameParser : Function!(IndividualResult, Maybe!Game)
{
	Game game;
	override OutputType opCall(InputType individualResult)
	{
		auto g = game.add(individualResult);
		if (!g.isNull)
			game = Game();
		return g;
	}
}

auto gameParser()
{
	return new GameParser().eitherEither(IdentityFunction!EOF.get);
}

struct Game
{
	string[] players;
	int[] results;
	Maybe!Game add(IndividualResult pr)
	{
		import std.algorithm;
		players ~= pr.player;
		results ~= pr.result;
		if (players.length < 5)
			return Maybe!Game();
		assert (results.reduce!((a, b) => a + b) == 1000);
		players.length = 4;
		results.length = 4;
		return Maybe!Game(Game(this.players.dup, this.results.dup));
	}
}

class ScoreAccumulator(size_t size) : Function!(Either!(Maybe!Game, EOF), Maybe!(Result!size[]))
{
	Function!(Either!(Maybe!Game, EOF), Maybe!(Result!size[])) opCallImpl;
	this ()
	{
		this.opCallImpl = new F().maybeNothing!(Result!size[]).maybeBind.eitherFunction(new G().compose(MaybeReturn!(Result!size[]).get));
	}
	override Maybe!(Result!size[]) opCall(Either!(Maybe!Game, EOF) x)
	{
		return opCallImpl(x);
	}
	Result!size[string] results;
	Result!size[] getResult()
	{
		return results.values;
	}
	class F : Function!(Game, void)
	{
		override void opCall(Game x)
		{
			update(x);
		}
	}
	class G : Function!(EOF, Result!size[])
	{
		override Result!size[] opCall(EOF x)
		{
			return getResult();
		}
	}
	void update(Game game)
	{
		import std.algorithm, std.array, std.range;
		auto x = game.results.map!(r => (-3).reduce!((a, b) => a + 2 * (b < r))(game.results)).array;
		auto y = game.results.map!(r => (r == game.results.reduce!max)).array;
		auto z = 0.reduce!((a, b) => a + b)(y);
		auto score = game.results[].dup;
		score[] += -300 + x[] * 100 + y[] * 200 / z;
		debug (scoreaccumulator_update)
		{
			import std.stdio;
			stderr.writefln(
"results = %(% 3d%)
x       = %(% 3d%)
y       = %(% 3d%)
z       = %d
score   = %(% 3d%)", game.results, x, y, z, score);
		}
		foreach (pr; game.players.zip(score))
		{
			pragma(msg, typeid (typeof(pr[0] in results)));
			if (auto p = pr[0] in results)
				results[pr[0]].update(pr[1]);
			else
				results[pr[0]] = Result!size(pr[0]).update(pr[1]);
		}
	}
}

struct Result(size_t size)
{
	string label;
	int[] cumsum;
	int maximum = int.min;
	auto update(int score)
	{
		debug (result_update)
		{
			import std.stdio;
			stderr.writefln("update by %d:", score);
			stderr.writefln("from: %(%d, %)", cumsum);
		}
		import std.array, std.algorithm;
		cumsum.length += 1;
		cumsum[] += score;
//		if (size < cumsum.length) cumsum.popFront;
		if (size <= cumsum.length)
			maximum = maximum.max(cumsum[$-size]);
		debug (result_update)
		{
			import std.stdio;
			stderr.writefln("to: %(%d, %)", cumsum);
		}
		return this;
	}
	void toString(scope void delegate(const(char)[]) sink)
	{
		import std.conv;
		sink(label);
		foreach_reverse (c; cumsum ~ maximum)
			sink("\t" ~ c.to!string);
	}
}



void main(string[] args)
{
	enum threshold = 6;
	import std.stdio, std.algorithm, std.conv;
	auto scoreParser =
		new ScoreParser().compose(
		gameParser()).compose(
		new ScoreAccumulator!threshold()).compose(
		new ArrayPrinter!(Result!threshold)().maybeSink
		);
	foreach (line; File(1 < args.length ? args[1] : "sample.in").byLine.map!(to!string))
		scoreParser(line);
}
