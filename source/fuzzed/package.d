module fuzzed;

import std.string;

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
        if (pattern[patternIdx] == value[valueIdx])
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

@("empty pattern") unittest
{
    import unit_threaded;
    import unit_threaded.should;

    fuzzyMatch("test", "").shouldNotBeNull;
}

@("normal match") unittest
{
    import unit_threaded;
    import unit_threaded.should;

    fuzzyMatch("test", "tt").positions.shouldEqual([0, 3]);
}

@("not matching") unittest
{
    import unit_threaded;
    import unit_threaded.should;

    fuzzyMatch("test", "test1").shouldBeNull;
}

@("exact match") unittest
{
    import unit_threaded;
    import unit_threaded.should;

    fuzzyMatch("test", "test").positions.shouldEqual([0, 1, 2, 3]);
}
