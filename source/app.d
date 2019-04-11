import fuzzed;

import colored;
import deimos.ncurses;
import nice.ui.elements;
import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.format;
import std.range;
import std.stdio;
import std.string;

/// Produce ncurses attributes array for a stringish thing with highlights and selection style
auto attributes(T)(T s, immutable ulong[] highlights, bool selected, int offset = 0)
{
    Attr[] result = s.map!(_ => selected ? Attr.bold : Attr.normal).array;
    foreach (index; highlights)
    {
        if (index + offset < result.length)
        {
            result[index + offset] |= Attr.standout;
        }
    }
    return result;
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

struct Pattern
{
    string pattern;
}

struct Matches
{
    immutable(Match)[] matches;
    struct Request
    {
        Tid tid;
        ulong offset;
        ulong height;
    }
}

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
    }

    void update(string pattern)
    {
        this.pattern = pattern;
        this.matches = all.map!(line => fuzzyMatch(line, pattern))
            .filter!(match => match !is null).array;
    }
}

void modelLoop()
{
    auto model = new Model;
    bool finished = false;
    while (!finished)
    {
        receive((Pattern pattern) { model.update(pattern.pattern); }, (string line) {
            model.append(line);
        }, (StatusInfo.Request request) {
            request.tid.send(StatusInfo(model.matches.length, model.all.length, model.pattern));
        }, (Matches.Request request) {
            request.tid.send(Matches(cast(immutable(Match)[]) model.matches.dup));
        }, (OwnerTerminated terminated) { finished = true; },);
    }
}

/// The working horse
class UiList(S, T)
{
    S curses;
    T screen;
    int height;
    int selection;
    int offset;

    Tid model;
    immutable(Match)[] allMatches;

    this(S curses, T screen, Tid model)
    {
        this.curses = curses;
        this.screen = screen;
        this.selection = 0;
        this.offset = 0;
        this.model = model;
        resize;
    }

    /// return selection
    string get()
    {
        return allMatches[selection].value;
    }

    void resize()
    {
        height = screen.height - 2;
        selection = 0;
        offset = 0;
    }

    void selectUp()
    {
        if (selection < allMatches.length - 1)
        {
            selection++;
            // correct selection to be in the right range.
            // we check only the upper limit, as we just incremented the selection
            while (selection >= offset + height)
            {
                offset++;
            }
        }
    }

    void selectDown()
    {
        if (selection > 0)
        {
            selection--;
            // correct selection to be in the right range.
            // we check only the lower limit, as we just decremented the selection
            while (selection < offset)
            {
                offset--;
            }
        }
    }

    /// render the list
    private void render()
    {
        model.send(Matches.Request(thisTid, height, offset));
        receive((Matches response) { allMatches = response.matches; },);
        auto matches = allMatches[min(allMatches.length,
                offset) .. min(allMatches.length, offset + height)];
        foreach (index, match; matches)
        {
            auto y = height - index.to!int - 1;
            bool selected = index == selection - offset;
            auto text = (selected ? "> %s" : "  %s").format(match.value).take(screen.width);
            screen.addstr(y, 0, text, text.attributes(match.positions, selected, 2), OOB.ignore);
        }
    }
}

/// factory for List(S, T)
auto uiList(S, T)(S curses, T screen, Tid model)
{
    return new UiList!(S, T)(curses, screen, model);
}

/// Statusline
class UiStatus(S, T)
{
    S curses;
    T screen;
    Tid model;
    this(S curses, T screen, Tid model)
    {
        this.curses = curses;
        this.screen = screen;
        this.model = model;
    }

    auto resize()
    {
        return this;
    }

    auto render()
    {
        model.send(StatusInfo.Request(thisTid));
        StatusInfo statusInfo;
        receive((StatusInfo response) { statusInfo = response; });

        auto matches = statusInfo.matches;
        auto all = statusInfo.all;
        auto pattern = statusInfo.pattern;

        auto trimmedCounter = "%s/%s".format(matches, all).take(screen.width - 2);
        screen.addstr(screen.height - 2, 2, trimmedCounter);

        auto trimmedPattern = "> %s".format(pattern).take(screen.width - 2);
        screen.addstr(screen.height - 1, 0, trimmedPattern, trimmedPattern.attributes([], true));
        return this;
    }

    auto selectUp()
    {
        return this;
    }

    auto selectDown()
    {
        return this;
    }
}

/// factory for Status(S, T)
auto uiStatus(S, T)(S curses, T screen, Tid model)
{
    return new UiStatus!(S, T)(curses, screen, model);
}

/// The ui made out of List and Status
class Ui(S, T)
{
    S curses;
    T screen;
    UiList!(S, T) list;
    UiStatus!(S, T) status;
    this(S curses, T screen, Tid model)
    {
        this.curses = curses;
        this.screen = screen;
        this.list = uiList(curses, screen, model);
        this.status = uiStatus(curses, screen, model);
    }

    auto get()
    {
        return list.get;
    }

    auto render()
    {
        try
        {
            // ncurses
            screen.clear;

            // own api
            list.render;
            status.render;

            // ncurses
            screen.refresh;
            curses.update;
            return this;
        }
        catch (Exception e)
        {
            return render;
        }
    }

    auto resize()
    {
        list.resize;
        status.resize;
        return render;
    }

    auto selectUp()
    {
        list.selectUp;
        status.selectUp;
        return render;
    }

    auto selectDown()
    {
        list.selectDown;
        status.selectDown;
        return render;
    }
}

/// factory for UI(S, T)
auto ui(S, T)(S curses, T screen, Tid model)
{
    return new Ui!(S, T)(curses, screen, model);
}

/// State of the search
struct State
{
    bool finished;
    string result;
    string pattern;
}

/// handle input events
State handleKey(S, T)(S input, T ui, Tid model, State state)
{
    if (input.isSpecialKey)
    {
        switch (input.key)
        {
        case Key.up:
            ui.selectUp;
            break;
        case Key.down:
            ui.selectDown;
            break;
        case Key.resize:
            ui.resize;
            break;
        default:
            break;
        }
    }
    else
    {
        switch (input.chr)
        {
        case 13:
            state.finished = true;
            state.result = ui.get;
            break;
        case 127:
            if (state.pattern.length > 0)
            {
                state.pattern = state.pattern[0 .. $ - 1];
                model.send(Pattern(state.pattern));
            }
            break;
        default:
            state.pattern ~= input.chr;
            model.send(Pattern(state.pattern));
            break;
        }
    }
    return state;
}

import std.stdio;

void readerLoop(shared Wrapper input, Tid model)
{

    foreach (string line; lines((cast() input).o))
    {
        model.send(line.strip.idup);
    }
}

class Wrapper
{
    File o;
    this(File o)
    {
        this.o = o;
    }

    ubyte[] read(ubyte[] buffer)
    {
        return (cast() o).rawRead(buffer);
    }
}

/// the main
void main(string[] args)
{

    import core.sys.posix.unistd;
    import std.stdio;

    File copy;
    copy.fdopen(dup(stdin.fileno));

    shared w = cast(shared)(new Wrapper(copy));

    stdin.reopen("/dev/tty");

    auto model = spawnLinked(&modelLoop);
    auto reader = spawnLinked(&readerLoop, w, model);

    // dfmt off
    State state =
    {
        finished: false,
        pattern : "",
        result : "",
    };
    // dfmt on
    {
        // dfmt off
        Curses.Config config =
        {
            disableEcho: true,
            initKeypad : true,
            cursLevel : 0,
        };
        // dfmt on
        auto curses = new Curses(config);
        scope (exit)
        {
            destroy(curses);
        }

        auto screen = curses.stdscr;
        screen.timeout(100);
        auto ui = ui(curses, screen, model);
        ui.render;
        while (!state.finished)
        {
            try
            {
                auto input = screen.getwch;
                state = handleKey(input, ui, model, state);
            }
            catch (Exception e)
            {
                writeln("...", e);
            }
            finally
            {
                ui.render;
            }
        }
    }
    if (state.result)
    {
        writeln(state.result);
    }
}
