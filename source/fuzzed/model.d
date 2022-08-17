module fuzzed.model;

import fuzzed.algorithm : fuzzyMatch, Match;
import std.algorithm : map, filter;
import std.array : array;
import std.concurrency : send, receive, Tid, OwnerTerminated;
import std.format : format;
import tui : Refresh;
import std.file : append;
import std.conv : to;

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

    /// Add one new line to the model
    void append(string line)
    {
        all ~= line;
        auto match = fuzzyMatch(line, pattern);
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
        this.matches = all
            .map!(line => fuzzyMatch(line, pattern))
            .filter!(match => match !is null)
            .array;
        // dfmt on
    }

    override string toString()
    {
        // dfmt off
        return "Model(all.length=%s, pattern=%s, matches.length=%s)"
            .format(all.length, pattern, matches.length);
        // dfmt on
    }
}

/// Async API for a model
void modelLoop(Tid listener)
{
    try
    {
        auto model = new Model;
        bool finished = false;
        while (!finished)
        {
            try
            {
                //dfmt off
                receive(
                    (Pattern pattern)
                    {
                        // change of pattern
                        model.update(pattern.pattern);
                        listener.send(Refresh());
                    },
                    (string line)
                    {
                        // new line added
                        model.append(line);
                        listener.send(Refresh());
                    },
                    (Tid l)
                    {
                        listener = l;
                    },
                    (Tid backChannel, StatusInfo.Request request)
                    {
                        // get status info
                        backChannel.send(StatusInfo(model.matches.length, model.all.length, model.pattern));
                    },
                    (Tid backChannel, Matches.Request request)
                    {
                        // get match details
                        backChannel.send(Matches(cast(immutable(Match)[]) model.matches.dup, model.all.length));
                    },
                    (OwnerTerminated terminated)
                    {
                        "log.log".append("model-thread: Owner terminated\n");
                        // finish up
                        finished = true;
                    },
                );
            } catch (Exception e) {
                "log.log".append(e.to!string);
            }
            // dfmt on
        }
        "log.log".append("model done\n");
    }
    catch (Exception e)
    {
        "log.log".append("modelLoop broken: %s".format(e));
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
        string toString()
        {
            return "StatusInfo.Request";
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
        string toString()
        {
            return "Matches.Request";
        }
    }
}

@("length of empty array") unittest
{
    int[] data;
    data.length.should == 0;
}
