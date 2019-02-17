import fuzzed;
import nice.ui.elements;
import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.range;
import std.range;
import std.stdio;
import std.string;

/// Produce ncurses attributes array for a string out of a match
auto attributed(Match match, bool selected)
{
    Attr[] res = match.value.map!(c => selected ? Attr.bold : Attr.normal).array;
    foreach (index; match.positions)
    {
        if (index < res.length)
        {
            res[index] |= Attr.standout;
        }
    }
    return res;
}

/// Model for the list and the statusbar
class Model
{
    interface Listener
    {
        void changed();
    }

    public string[] all;
    public Match[] matches;
    private Listener listener;
    this(string[] all)
    {
        this.all = all;
        update("");
    }

    void update(string pattern)
    {
        this.matches = all.map!(a => fuzzyMatch(a, pattern)).filter!(a => a !is null).array;
        if (listener)
        {
            listener.changed;
        }
    }

    auto setListener(Listener listener)
    {
        this.listener = listener;
        listener.changed;
        return this;
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

    Model model;

    this(S curses, T screen, Model model)
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
        return model.matches[selection].value;
    }

    void changed()
    {
        offset = 0;
        selection = 0;
    }

    void resize()
    {
        height = screen.height - 1;
        selection = 0;
        offset = 0;
    }

    private int selectionToScreen()
    {
        return height - 1 - selection + offset;
    }

    void selectUp()
    {
        if (selection < model.matches.length - 1)
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
        auto matches = model.matches[offset .. min(model.matches.length, offset + height)];
        foreach (index, match; matches)
        {
            auto y = height - index.to!int - 1;
            auto trimmed = match.value[0 .. min(screen.width - 2, match.value.length)];
            screen.addstr(y, 2, trimmed, match.attributed(index == selection - offset), OOB.ignore);
        }
        screen.addstr(selectionToScreen, 0, ">", Attr.bold);
    }
}

/// factory for List(S, T)
auto uiList(S, T)(S curses, T screen, Model model)
{
    return new UiList!(S, T)(curses, screen, model);
}

/// Statusline
class UiStatus(S, T)
{
    S curses;
    T screen;
    Model model;
    this(S curses, T screen, Model model)
    {
        this.curses = curses;
        this.screen = screen;
        this.model = model;
    }

    void changed()
    {
    }

    auto resize()
    {
        return this;
    }

    auto render()
    {
        screen.addstr(screen.height - 1, 2,
                "%s/%s".format(model.matches.length, model.all.length));
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
auto uiStatus(S, T)(S curses, T screen, Model model)
{
    return new UiStatus!(S, T)(curses, screen, model);
}

/// The ui made out of List and Status
class Ui(S, T) : Model.Listener
{
    S curses;
    T screen;
    UiList!(S, T) list;
    UiStatus!(S, T) status;
    this(S curses, T screen, Model model)
    {
        this.curses = curses;
        this.screen = screen;
        this.list = uiList(curses, screen, model);
        this.status = uiStatus(curses, screen, model);
        model.setListener(this);
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

    void changed()
    {
        list.changed;
        status.changed;
        render;
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
auto ui(S, T)(S curses, T screen, Model model)
{
    return new Ui!(S, T)(curses, screen, model);
}

/// reopen a tty input if we got piped in
string[] prepareInput()
{
    import core.sys.posix.unistd;

    if (!isatty(0))
    {
        string[] res = stdin.byLineCopy.map!(s => s.strip).array;
        stdin.reopen("/dev/tty");
        return res;
    }
    else
    {
        return [];
    }
}

/// State of the search
struct State
{
    bool finished;
    string result;
    string pattern;
}

/// handle input events
State handleKey(S, T)(S input, T ui, Model model, State state)
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
                model.update(state.pattern);
            }
            break;
        default:
            state.pattern ~= input.chr;
            model.update(state.pattern);
            break;
        }
    }
    return state;
}

/// the main
void main(string[] args)
{

    auto model = new Model(prepareInput);

    State state = {finished:
    false, pattern : "", result : ""};
    {
        Curses.Config config = {
        disableEcho:
            true, initKeypad : true, cursLevel : 0
        };
        auto curses = new Curses(config);
        scope (exit)
        {
            destroy(curses);
        }

        auto screen = curses.stdscr;
        auto ui = ui(curses, screen, model);
        while (!state.finished)
        {
            auto input = screen.getwch;
            state = handleKey(input, ui, model, state);
        }
    }
    if (state.result)
    {
        writeln(state.result);
    }
}
