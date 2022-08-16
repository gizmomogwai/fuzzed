module fuzzed.model;

import fuzzed.algorithm;
import std.algorithm;
import std.array;
import std.concurrency;
import std.format : format;
import tui : Refresh;

/// Model for the list and the statusbar
class Model
{
    public string[] all;
    public string pattern;
    public Match[] matches;
    this()
    {
        all = [];
        update("");
    }

    void append(string line)
    {
        all ~= line;
        auto match = fuzzyMatch(line, pattern);
        if (match)
        {
            this.matches ~= match;
        }
    }

    void update(string pattern)
    {
        this.pattern = pattern;
        updateMatches();
    }

    void updateMatches()
    {
        // dfmt off
        this.matches = all
            .map!(line => fuzzyMatch(line, pattern))
            .filter!(match => match !is null)
            .array;
        // dftm on
    }
    override string toString()
    {
        return "Model(all.length=%s, pattern=%s, matches.length=%s)".format(all.length, pattern, matches.length);
    }
}

void modelLoop(Tid listener)
{
    import std.file : append;
    import std.conv : to;

    try {
    auto model = new Model;
    bool finished = false;
    while (!finished)
    {
        try {
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
            (StatusInfo.Request request)
            {
                "log.log".append(request.to!string);
                "log.log".append(model.to!string);
                // get status info
                request.tid.send(StatusInfo(model.matches.length, model.all.length, model.pattern));
                "log.log".append("... done\n");
            },
            (Matches.Request request)
            {
                "log.log".append(request.to!string);
                // get match details
                request.tid.send(Matches(cast(immutable(Match)[]) model.matches.dup, model.all.length));
                "log.log".append("%s ... done".format(request.to!string));
            },
            (OwnerTerminated terminated)
            {
                "log.log".append("model-thread: Owner terminated\n");
                // finish up
                finished = true;
            },
        );
        } catch (Exception e) {
            "exception.log".append(e.to!string);
        }
        // dfmt on
    }
    "log.log".append("model done\n");
    } catch (Exception e)
    {
        "log.log".append("modelLoop broken: %s".format(e));
    }
}

struct Pattern
{
    string pattern;
}

struct StatusInfo
{
    ulong matches;
    ulong all;
    string pattern;
    struct Request
    {
        Tid tid;
        string toString()
        {
            return "StatusInfo.Request";
        }
    }
}

struct Matches
{
    immutable(Match)[] matches;
    ulong total;
    struct Request
    {
        Tid tid;
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
    import unit_threaded;
    int[] data;
    data.length.should == 0;
}
