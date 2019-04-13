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
    ulong total;
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

class Details
{
    ulong total;
    ulong matches;
    ulong offset;
    ulong selection;
}
/// The working horse
class UiList(S, T)
{
    S curses;
    T screen;
    int height;
    Details details;

    Tid model;
    immutable(Match)[] allMatches;

    this(S curses, T screen, Tid model)
    {
        this.curses = curses;
        this.screen = screen;
        this.details = new Details;
        this.model = model;
        resize;
    }

    /// return selection
    string get()
    {
        if (details.selection == -1)
        {
            return "";
        }
        return allMatches[details.selection].value;
    }

    void resize()
    {
        height = screen.height - 2;
        details.offset = 0;
        details.selection = 0;
    }

    void selectUp()
    {
        if (details.selection < allMatches.length - 1)
        {
            details.selection++;
            // correct selection to be in the right range.
            // we check only the upper limit, as we just incremented the selection
            while (details.selection >= details.offset + height)
            {
                details.offset++;
            }
        }
    }

    void selectDown()
    {
        if (details.selection > 0)
        {
            details.selection--;
            // correct selection to be in the right range.
            // we check only the lower limit, as we just decremented the selection
            while (details.selection < details.offset)
            {
                details.offset--;
            }
        }
    }

    private void adjustOffsetAndSelection()
    {
        details.selection = min(details.selection, allMatches.length - 1);

        if (allMatches.length < height)
        {
            details.offset = 0;
        }
        if (details.selection < details.offset)
        {
            details.offset = details.selection;
        }
    }
    /// render the list
    private void render()
    {
        model.send(Matches.Request(thisTid, height, details.offset));
        //dfmt off
        receive(
          (Matches response)
          {
              allMatches = response.matches;
              details.total = response.total;
              details.matches = allMatches.length;
          },
        );
        //dfmt on

        adjustOffsetAndSelection;
        auto matches = allMatches[min(allMatches.length,
                details.offset) .. min(allMatches.length, details.offset + height)];
        foreach (index, match; matches)
        {
            auto y = height - index.to!int - 1;
            bool selected = index == details.selection - details.offset;
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
    Details details;
    this(S curses, T screen, Tid model, Details details)
    {
        this.curses = curses;
        this.screen = screen;
        this.model = model;
        this.details = details;
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

        auto trimmedCounter = "%s/%s (selection %s/offset %s)".format(details.matches,
                details.total, details.selection, details.offset).take(screen.width - 2);
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
auto uiStatus(S, T)(S curses, T screen, Tid model, Details details)
{
    return new UiStatus!(S, T)(curses, screen, model, details);
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
        this.status = uiStatus(curses, screen, model, this.list.details);
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
            return this;
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
            mode : Curses.Mode.halfdelay,
        };
        // dfmt on
        auto curses = new Curses(config);
        scope (exit)
        {
            destroy(curses);
        }
        auto screen = curses.stdscr;
        screen.timeout(50);

        auto ui = ui(curses, screen, model);
        while (!state.finished)
        {
            try
            {
                auto input = screen.getwch;
                state = handleKey(input, ui, model, state);
            }
            catch (Exception e)
            {
                //                writeln("...", e);
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
