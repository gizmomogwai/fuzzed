module fuzzed.algorithm;

import std.algorithm : all, equal, map;
import std.ascii : asciiToLower = toLower;
import std.format : formattedWrite;
import std.range : empty, enumerate, front, popFront;
import std.string : representation;
import std.uni : byGrapheme, toLower;

version (unittest)
{
    import std.range : walkLength;
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

    void toString(scope void delegate(const(char)[]) sink) const
    {
        sink.formattedWrite!"Match(value=%s, pattern=%s, positions=%s, index=%s)"(value,
                pattern, positions, index);
    }
}

/++ Fuzzy matches pattern on value (case insensitive).
 + The graphemes of pattern need to appear in the same order in value.
 + Returns: a Match with the grapheme positions in value, or null.
 +/
Match fuzzyMatch(string value, string pattern, size_t index)
{
    ulong[] positions;
    // fast path: for pure ascii every char is one grapheme (except "\r\n")
    const matched = value.isAscii && pattern.isAscii
        ? matchPositions!((v, p) => v.asciiToLower == p.asciiToLower)(
                value.representation, pattern.representation, positions)
        : matchPositions!((v, p) => v[].map!toLower.equal(p[]))(
                value.byGrapheme, pattern.toLower.byGrapheme, positions);
    return matched ? new Match(value, pattern, positions, index) : null;
}

/// Collects the positions in value where the elements of pattern are found in order.
private bool matchPositions(alias equals, Value, Pattern)(Value value,
        Pattern pattern, ref ulong[] positions)
{
    foreach (position, element; value.enumerate)
    {
        if (pattern.empty)
        {
            break;
        }
        if (equals(element, pattern.front))
        {
            positions ~= position;
            pattern.popFront;
        }
    }
    return pattern.empty;
}

private bool isAscii(string s)
{
    return s.representation.all!(c => c < 0x80);
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

@("case insensitive") unittest
{
    fuzzyMatch("TeSt", "tS", 0).positions.should == [0, 2];
    fuzzyMatch("Äpfel", "äf", 0).positions.should == [0, 2];
}

@("positions are grapheme indices") unittest
{
    "noël".byGrapheme.walkLength.should == 4;
    fuzzyMatch("xäy", "y", 0).positions.should == [2];
    fuzzyMatch("noël", "l", 0).positions.should == [3];
}

@("combining characters only match as a whole") unittest
{
    fuzzyMatch("noël", "e", 0).shouldBeNull;
    fuzzyMatch("noël", "ë", 0).positions.should == [2];
}

@("ascii and unicode path agree") unittest
{
    fuzzyMatch("TeSt Ä", "tsä", 0).positions.should == [0, 2, 5];
    fuzzyMatch("TeSt A", "tsa", 0).positions.should == [0, 2, 5];
}
