module fuzzed.algorithm;

import std.format : format;
import std.uni : toLower;

version (unittest)
{
    import std.conv : text;
    import std.range : walkLength;
    import std.stdio : writeln;
    import std.uni : byGrapheme;
    import unit_threaded;
}

class Match
{
    /// Complete value of the match
    string value;
    /// Searchpattern
    string pattern;
    /// Positions that matched the search pattern
    ulong[] positions;
    /// Index in input dataset
    size_t index;
    this(string value, string pattern, ulong[] positions, size_t index)
    {
        this.value = value;
        this.pattern = pattern;
        this.positions = positions;
        this.index = index;
    }

    void toString(Sink, Format)(Sink sink, Format format) const
    {
        sink(format!("Match(value=%s, pattern=%s, positions=%s, index=%s)")(value,
                pattern, positions, index));
    }
}

/++ Fuzzymatches pattern on value.
 + The characters in pattern need to be in the same order as in value to match.
 +/
auto fuzzyMatch(string value, string pattern, size_t index)
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
        return new Match(value, pattern, positions, index);
    }
    return null;
}

@("empty pattern") unittest
{
    fuzzyMatch("test", "", 0).shouldNotBeNull;
}

@("normal match") unittest
{
    fuzzyMatch("test", "tt", 0).positions.should == [0, 3];
}

@("not matching") unittest
{
    fuzzyMatch("test", "test1", 0).shouldBeNull;
}

@("exact match") unittest
{
    fuzzyMatch("test", "test", 0).positions.should == [0, 1, 2, 3];
}

@("check graphemes") unittest
{
    import std.range.primitives : walkLength;

    "ä".byGrapheme.walkLength.shouldEqual(1);
    "noe\u0308l".byGrapheme.walkLength.should == 4;
}

@("grapheme") unittest
{
    auto text = "noe\u0308l"; // noël using e + combining diaeresis
    assert(text.walkLength == 5); // 5 code points

    auto gText = text.byGrapheme;
    foreach (g; gText)
    {
        string s = g[].text;
        writeln(s);
    }
}
