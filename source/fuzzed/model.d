module fuzzed.model;

import fuzzed.algorithm : fuzzyMatch, Match;
import std.algorithm : map, filter, startsWith, equal;
import std.array : array;
import std.concurrency : send, receive, Tid, OwnerTerminated;
import std.conv : to;
import std.file : append;
import std.format : format;
import std.range : iota, zip;
import std.uni : byGrapheme;

version (unittest)
{
    import unit_threaded;
}

/// Model for the list and the statusbar
class Model
{
    public string[] all;
    public string pattern;
    public Match[] matches;

    /// Create an empty model
    this()
    {
        all = [];
        update("");
    }

    /// Replace all data
    void setData(string[] data)
    {
        all = data;
        updateMatches;
    }

    /// Add one new line to the model
    void append(string line)
    {
        append([line]);
    }

    /// Add several new lines to the model
    void append(string[] lines)
    {
        const firstIndex = all.length;
        all ~= lines;
        foreach (offset, line; lines)
        {
            auto match = fuzzyMatch(line, pattern, firstIndex + offset);
            if (match)
            {
                this.matches ~= match;
            }
        }
    }

    /// Update matches for a new pattern
    void update(string pattern)
    {
        // Appending a combining mark can change the final grapheme, not just add one.
        const refine = pattern.byGrapheme.startsWith!(
            (left, right) => left[].equal(right[]))(this.pattern.byGrapheme);
        this.pattern = pattern;
        if (refine)
        {
            refineMatches();
        }
        else
        {
            updateMatches();
        }
    }

    /// Recalc matches from the current matches
    private void refineMatches()
    {
        // dfmt off
        this.matches = matches
            .map!(match => fuzzyMatch(match.value, pattern, match.index))
            .filter!(match => match !is null)
            .array;
        // dfmt on
    }

    /// Calc all matches
    private void updateMatches()
    {
        // dfmt off
        this.matches = zip(all, iota(0, all.length))
            .map!(t => fuzzyMatch(t[0], pattern, t[1]))
            .filter!(match => match !is null)
            .array;
        // dfmt on
    }

    void toString(Sink, Format)(Sink sink, Format format) const
    {
        sink(format!"Model(all.length=%s, pattern=%s, matches.length=%s)"(all.length,
                pattern, matches.length));
    }
}

/// New Pattern
struct Pattern
{
    string pattern;
}

/// Provide StatusInfo
struct StatusInfo
{
    ulong matches;
    ulong all;
    string pattern;
    /// Request for StatusInfo
    struct Request
    {
        void toString(Sink, Format)(Sink sink, Format format) const
        {
            sink("StatuInfo.Request");
        }
    }
}

/// Provide Matches to caller
struct Matches
{
    immutable(Match)[] matches;
    ulong total;
    /// Request to get the matches
    struct Request
    {
        ulong offset;
        ulong height;
        void toString(Sink, Format)(Sink sink, Format format) const
        {
            sink("Matches.Request");
        }
    }
}

@("length of empty array") unittest
{
    int[] data;
    data.length.should == 0;
}

@("refining the pattern gives the same matches as a full scan") unittest
{
    auto model = new Model();
    model.setData(["abc", "acb", "xyz", "ab"]);
    model.update("a");
    model.update("ab");
    model.matches.map!(match => match.index).array.should == [0, 1, 3];
    model.update("abc");
    model.matches.map!(match => match.index).array.should == [0];
    model.update("b");
    model.matches.map!(match => match.index).array.should == [0, 1, 3];
}

@("appended lines get their own index") unittest
{
    auto model = new Model();
    model.append("a1");
    model.append(["a2", "b", "a3"]);
    model.update("a");
    model.matches.map!(match => match.index).array.should == [0, 1, 3];
    model.append(["a4", "a5"]);
    model.matches.map!(match => match.index).array.should == [0, 1, 3, 4, 5];
}

@("extending a grapheme must search all lines again") unittest
{
    auto model = new Model();
    model.setData(["noe\u0308l", "noel"]);
    model.update("e");
    model.matches.map!(match => match.index).array.should == [1];
    model.update("e\u0308");
    model.matches.map!(match => match.index).array.should == [0];
    model.matches[0].positions.should == [2];
}
