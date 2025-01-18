module fuzzed.model;

import fuzzed.algorithm : fuzzyMatch, Match;
import std.algorithm : map, filter;
import std.array : array;
import std.concurrency : send, receive, Tid, OwnerTerminated;
import std.conv : to;
import std.file : append;
import std.format : format;
import std.range : iota, zip;
import tui : Refresh;

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
        all ~= line;
        import std.file:append;"log.log".append(format("\n\nall: %s", all));
        auto match = fuzzyMatch(line, pattern, all.length - 1);
        if (match)
        {
            this.matches ~= match;
        }
    }

    /// Update matches for a new pattern
    void update(string pattern)
    {
        this.pattern = pattern;
        updateMatches();
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
