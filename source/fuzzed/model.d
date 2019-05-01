module fuzzed.model;

import fuzzed.algorithm;
import std.algorithm;
import std.array;
import std.concurrency;

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
        updateMatches;
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
}

void modelLoop()
{
    auto model = new Model;
    bool finished = false;
    while (!finished)
    {
        //dfmt off
        receive(
            (Pattern pattern)
            {
                model.update(pattern.pattern);
            },
            (string line)
            {
                model.append(line);
            },
            (StatusInfo.Request request)
            {
                request.tid.send(StatusInfo(model.matches.length, model.all.length, model.pattern));
            },
            (Matches.Request request)
            {
                request.tid.send(Matches(cast(immutable(Match)[]) model.matches.dup, model.all.length));
            },
            (OwnerTerminated terminated)
            {
                finished = true;
            },
        );
        // dfmt on
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
    }
}
