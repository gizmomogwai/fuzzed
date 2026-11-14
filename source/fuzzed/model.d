module fuzzed.model;

import fuzzed.algorithm : fuzzyMatch, Match;
public import fuzzed.algorithm : Candidate;
import fuzzed.memory : SelectionMemory;
import std.algorithm : map, filter, startsWith, equal, sort;
import std.array : array;
import std.concurrency : send, receive, Tid, OwnerTerminated;
import std.conv : to;
import std.file : append;
import std.format : format;
import std.uni : byGrapheme;

/// Conservative sorting cutoff; not a real-time guarantee.
enum MAXIMUM_MEMORY_RANKED_MATCHES = 1000;

/// Model for the list and the statusbar
class Model
{
    public Candidate[] all;
    public string pattern;
    public Match[] matches;
    private SelectionMemory memory;

    /// Create an empty model
    this(SelectionMemory memory = null)
    {
        this.memory = memory;
        all = [];
        update("");
    }

    /// Replace all data
    void setData(string[] data)
    {
        all = [];
        matches = [];
        append(data);
    }

    /// Add one new line to the model
    void append(string line)
    {
        append([line]);
    }

    /// Add several new lines to the model
    void append(string[] lines)
    {
        const previousMatches = matches.length;
        foreach (line; lines)
        {
            // dfmt off
            auto candidate = new Candidate(line,
                                           memory is null ? 0 : memory.selectionCount(line),
                                           all.length);
            // dfmt on
            all ~= candidate;
            auto match = fuzzyMatch(candidate, pattern);
            if (match)
            {
                this.matches ~= match;
            }
        }
        orderMatches(previousMatches);
    }

    /// Update matches for a new pattern
    void update(string pattern)
    {
        const newGraphemeAdded = pattern.byGrapheme.startsWith!((left,
                right) => left[].equal(right[]))(this.pattern.byGrapheme);
        this.pattern = pattern;
        if (newGraphemeAdded)
        {
            filterExistingMatches();
        }
        else
        {
            matchAllCandidates();
        }
    }

    /// Recalc matches from the current matches
    private void filterExistingMatches()
    {
        // dfmt off
        this.matches = matches
            .map!(match => fuzzyMatch(match.candidate, pattern))
            .filter!(match => match !is null)
            .array;
        // dfmt on
        orderMatches();
    }

    /// Calc all matches
    private void matchAllCandidates()
    {
        // dfmt off
        this.matches = all
            .map!(candidate => fuzzyMatch(candidate, pattern))
            .filter!(match => match !is null)
            .array;
        // dfmt on
        orderMatches();
    }

    private void orderMatches(size_t previousMatches = 0)
    {
        if (memory is null)
        {
            return;
        }
        if (matches.length > MAXIMUM_MEMORY_RANKED_MATCHES)
        {
            // restore input order of the matches if we cross the maximum sort boundary
            // needed, because before that the matches have been sorted according to
            // selectionCount and index
            if (previousMatches <= MAXIMUM_MEMORY_RANKED_MATCHES)
            {
                matches[0 .. previousMatches].sort!((left, right) => left.index < right.index);
            }
            return;
        }

        // dfmt off
        matches.sort!((left, right) =>
                      left.selectionCount > right.selectionCount ||
                      (left.selectionCount == right.selectionCount && left.index < right.index));
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
