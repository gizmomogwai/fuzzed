module fuzzed.algorithm;
import std.typecons;

class Match
{
    string value;
    string pattern;
    ulong[] positions;
    this(string value, string pattern, ulong[] positions)
    {
        this.value = value;
        this.pattern = pattern;
        this.positions = positions;
    }
}

auto fuzzyMatch(string value, string pattern)
{
    ulong[] positions;
    ulong valueIdx = 0;
    ulong patternIdx = 0;
    while ((valueIdx < value.length) && (patternIdx < pattern.length))
    {
        import std.uni;

        if (pattern[patternIdx].toLower == value[valueIdx].toLower)
        {
            positions ~= valueIdx;
            patternIdx++;
        }
        valueIdx++;
    }
    if (patternIdx == pattern.length)
    {
        return new Match(value, pattern, positions);
    }
    return null;
}

version (Have_unit_threaded)
{
    import unit_threaded;
    import unit_threaded.should;
}

@("empty pattern") unittest
{
    fuzzyMatch("test", "").shouldNotBeNull;
}

@("normal match") unittest
{
    fuzzyMatch("test", "tt").positions.shouldEqual([0, 3]);
}

@("not matching") unittest
{
    fuzzyMatch("test", "test1").shouldBeNull;
}

@("exact match") unittest
{
    fuzzyMatch("test", "test").positions.shouldEqual([0, 1, 2, 3]);
}
/+
@("check graphemes") unittest
{
    import std.uni;
    import std.range.primitives : walkLength;

    "ä".byGrapheme.walkLength.shouldEqual(1);
    "noe\u0308l".byGrapheme.walkLength.shouldEqual(5);
}
+/
