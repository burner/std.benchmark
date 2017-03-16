module valuegenerators;

import std.traits : isFloatingPoint, isNumeric, isSomeString;
import std.random : Random, uniform;

/* Return $(D true) if the passed $(D T) is a $(D Gen) struct.

A $(D Gen!T) is something that implicitly converts to $(D T), has a method
called $(D gen) that is accepting a $(D ref Random).

This module already brings Gens for numeric types, strings and ascii strings.

If a function needs to be benchmarked that has a parameter of custom type a
custom $(D Gen) is required.
*/
template isGen(T)
{
    static if (is(T : Gen!(S), S...))
        enum isGen = true;
    else
        enum isGen = false;
}

///
unittest
{
    static assert(!isGen!int);
    static assert(isGen!(Gen!(int, 0, 10)));
}

/** A $(D Gen) type that generates numeric values between the values of the
template parameter $(D low) and $(D high).
*/
struct Gen(T, T low, T high) if (isNumeric!T)
{
    alias Value = T;

    T value;

    void gen(ref Random gen)
    {
        static assert(low <= high);
        this.value = uniform!("[]")(low, high, gen);
    }

    ref T opCall()
    {
        return this.value;
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;

        static if (isFloatingPoint!T)
        {
            static if (low == T.min_normal && high == T.max)
            {
                formattedWrite(sink, "'%s'", this.value);
            }
        }
        else static if (low == T.min && high == T.max)
        {
            formattedWrite(sink, "'%s'", this.value);
        }
        else
        {
            formattedWrite(sink, "'%s' low = '%s' high = '%s'", this.value,
                low, high);
        }
    }

    alias opCall this;
}

/** A $(D Gen) type that generates unicode strings with a number of
charatacters that is between template parameter $(D low) and $(D high).
*/
struct Gen(T, size_t low, size_t high) if (isSomeString!T)
{
    static T charSet;
    static immutable size_t numCharsInCharSet;

    T value;

    static this()
    {
        import std.uni : unicode;
        import std.format : format;
        import std.range : chain, iota;
        import std.algorithm : map, joiner, count;
		import std.conv : to;
		import std.array : array;

        Gen!(T, low, high).charSet = to!T(chain(iota(0x21,
            0x7E).map!(a => to!T(cast(dchar) a)), iota(0xA1,
            0x1EF).map!(a => to!T(cast(dchar) a))).joiner.array);

        Gen!(T, low, high).numCharsInCharSet = count(charSet);
    }

    void gen(ref Random gen)
    {
        static assert(low <= high);
        import std.range : drop;
        import std.array : front, appender;
		import std.utf : byDchar;

        auto app = appender!T();
        app.reserve(high);
        size_t numElems = uniform!("[]")(low, high, gen);

        for (size_t i = 0; i < numElems; ++i)
        {
            size_t toSelect = uniform!("[)")(0, numCharsInCharSet, gen);
            app.put(charSet.byDchar().drop(toSelect).front);
        }

        this.value = app.data;
    }

    ref T opCall()
    {
        return this.value;
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;

        static if (low == 0 && high == 32)
        {
            formattedWrite(sink, "'%s'", this.value);
        }
        else
        {
            formattedWrite(sink, "'%s' low = '%s' high = '%s'", this.value,
                low, high);
        }
    }

    alias opCall this;
}

unittest
{
    import std.typetuple : TypeTuple;

    import std.range : iota;
    import std.array : empty;
	import std.meta : aliasSeqOf;

    auto r = Random(1337);
    foreach (T; TypeTuple!(string, wstring, dstring))
    {
        foreach (L; aliasSeqOf!(iota(0, 2)))
        {
            foreach (H; aliasSeqOf!(iota(L, 2)))
            {
                Gen!(T, L, H) a;
                a.gen(r);
                if (L)
                {
                    assert(!a.value.empty);
                }
            }
        }
    }
}

/// DITTO This random $(D string)s only consisting of ASCII character
struct GenASCIIString(size_t low, size_t high)
{
    static string charSet;
    static immutable size_t numCharsInCharSet;

    string value;

    static this()
    {
        import std.uni : unicode;
        import std.format : format;
        import std.range : chain, iota;
        import std.algorithm : map, joiner, count;
		import std.conv : to;
		import std.array : array;

        GenASCIIString!(low, high).charSet = to!string(chain(iota(0x21,
            0x7E).map!(a => to!char(cast(dchar) a)).array));

        GenASCIIString!(low, high).numCharsInCharSet = count(charSet);
    }

    void gen(ref Random gen)
    {
		import std.array : appender;

        auto app = appender!string();
        app.reserve(high);
        size_t numElems = uniform!("[]")(low, high, gen);

        for (size_t i = 0; i < numElems; ++i)
        {
            size_t toSelect = uniform!("[)")(0, numCharsInCharSet, gen);
            app.put(charSet[toSelect]);
        }

        this.value = app.data;
    }

    ref string opCall()
    {
        return this.value;
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;

        static if (low == 0 && high == 32)
        {
            formattedWrite(sink, "'%s'", this.value);
        }
        else
        {
            formattedWrite(sink, "'%s' low = '%s' high = '%s'", this.value,
                low, high);
        }
    }

    alias opCall this;
}

unittest
{
    import std.utf : validate;
    import std.array : empty;
    import std.exception : assertNotThrown;

    auto rnd = Random(1337);

    GenASCIIString!(5, 5) gen;
    gen.gen(rnd);
    auto str = gen();

    assert(!str.empty);
    assertNotThrown(validate(str));
}

/** This type will generate a $(D Gen!T) for all passed $(D T...).
Every call to $(D genValues) will call $(D gen) of all $(D Gen) structs
present in $(D values). The member $(D values) can be passed to every
function accepting $(D T...).
*/
struct RndValueGen(T...)
{
	static if(T.length > 0) {
		import std.meta : staticMap;

    	/* $(D Values) is a collection of $(D Gen) types created through
    	$(D ParameterToGen) of passed $(T ...).
    	*/
    	alias Values = staticMap!(ParameterToGen, T[1 .. $]);
    	/// Ditto
    	Values values;

    	string[] parameterNames = T[0];
	}

    /* The constructor accepting the required random number generator.
    Params:
        rnd = The required random number generator.
    */
    this(Random* rnd)
    {
        this.rnd = rnd;
    }

    /* The random number generator used to generate new value for all
    $(D values).
    */
    Random* rnd;

    /** A call to this member function will call $(D gen) on all items in
    $(D values) passing $(D the provided) random number generator
    */
    void genValues()
    {
		static if(T.length > 0) {
			foreach (ref it; this.values)
			{
				it.gen(*this.rnd);
			}
		}
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
		static if(T.length > 0) {
			import std.format : formattedWrite;

			foreach (idx, ref it; values)
			{
				formattedWrite(sink, "'%s' = %s ", parameterNames[idx], it);
			}
		}
    }
}

///
unittest
{
    auto rnd = Random(1337);
    auto generator = RndValueGen!(["i", "f"], Gen!(int, 0, 10), Gen!(float,
        0.0, 10.0))(&rnd);
    generator.genValues();

    static fun(int i, float f)
    {
        assert(i >= 0 && i <= 10);
        assert(f >= 0.0 && i <= 10.0);
    }

    fun(generator.values);
}

unittest
{
    auto rnd = Random(1337);
    auto generator = RndValueGen!()(&rnd);
    generator.genValues();
}

unittest
{
    static fun(int i, float f)
    {
        assert(i >= 0 && i <= 10);
        assert(f >= 0.0 && i <= 10.0);
    }

    auto rnd = Random(1337);
    auto generator = RndValueGen!(["i", "f"], Gen!(int, 0, 10), Gen!(float,
        0.0, 10.0))(&rnd);

    generator.genValues();
    foreach (i; 0 .. 1000)
    {
        fun(generator.values);
    }
}

/** A template that turns a $(D T) into a $(D Gen!T) unless $(D T) is
already a $(D Gen) or no $(D Gen) for given $(D T) is available.
*/
template ParameterToGen(T)
{
	import std.traits : isIntegral, isFloatingPoint, isSomeString;
    static if (isGen!T)
        alias ParameterToGen = T;
    else static if (isIntegral!T)
        alias ParameterToGen = Gen!(T, T.min, T.max);
    else static if (isFloatingPoint!T)
        alias ParameterToGen = Gen!(T, T.min_normal, T.max);
    else static if (isSomeString!T)
        alias ParameterToGen = Gen!(T, 0, 32);
    else static if (is(T : GenASCIIString!(S), S...))
        alias ParameterToGen = T;
    else
        static assert(false);
}

///
unittest
{
    alias GenInt = ParameterToGen!int;

    static fun(int i)
    {
        assert(i == 1337);
    }

    GenInt a;
    a.value = 1337;
    fun(a);
}

unittest
{
	import std.meta : AliasSeq, staticMap;

    foreach (T; AliasSeq!(byte, ubyte, ushort, short, uint, int, ulong, long,
            float, double, real, string, wstring,
            dstring))
    {
        alias TP = staticMap!(ParameterToGen, T);
        static assert(isGen!TP);
    }
}
