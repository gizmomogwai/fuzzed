module fuzzed.algorithm;

import std.uni;

class Match
{
    /// Complete value of the match
    string value;
    /// Searchpattern
    string pattern;
    /// Positions that matched the search pattern
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
}

@("empty pattern") unittest
{
    fuzzyMatch("test", "").shouldNotBeNull;
}

@("normal match") unittest
{
    fuzzyMatch("test", "tt").positions.should == [0, 3];
}

@("not matching") unittest
{
    fuzzyMatch("test", "test1").shouldBeNull;
}

@("exact match") unittest
{
    fuzzyMatch("test", "test").positions.should == [0, 1, 2, 3];
}

@("check graphemes") unittest
{
    import std.range.primitives : walkLength;

    "ä".byGrapheme.walkLength.shouldEqual(1);
    "noe\u0308l".byGrapheme.walkLength.should == 4;
}

@("grapheme") unittest
{
    import std.uni;
    import std.stdio;
    import std.conv;
    import std.range;

    auto text = "noe\u0308l"; // noël using e + combining diaeresis
    assert(text.walkLength == 5); // 5 code points

    auto gText = text.byGrapheme;
    foreach (g; gText)
    {
        string s = g[].text;
        writeln(s);
    }
}
