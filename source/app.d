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
    Attr[] res;
    res.length = match.value.length;
    foreach (index, ref a; res)
    {
        a = selected ? Attr.bold : Attr.normal;
    }
    foreach (p; match.positions)
    {
        if (p < res.length)
        {
            res[p] |= Attr.standout;
        }
    }
    return res;
}

/// Model for the list and the statusbar
class Model
{
    public string[] all;
    public Match[] matches;
    this(string[] all, string pattern)
    {
        this.all = all;
        this.matches = all.map!(a => fuzzyMatch(a, pattern)).filter!(a => a !is null).array;
    }
}

/// The working horse
class List(S, T)
{
    S curses;
    T screen;
    int height;
    int selection;
    int offset;

    Model model;

    this(S curses, T screen)
    {
        this.curses = curses;
        this.screen = screen;
        this.selection = 0;
        this.offset = 0;
        resize;
    }

    /// return selection
    string get()
    {
        return model.matches[selection].value;
    }

    /// update the model
    void update(Model model)
    {
        this.model = model;
        offset = 0;
        selection = 0;
    }

    void resize()
    {
        this.height = screen.height - 1;
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
            screen.addstr(y, 2, match.value[0 .. min(screen.width - 2,
                    match.value.length)], match.attributed(index == selection - offset), OOB.ignore);
        }
        screen.addstr(selectionToScreen, 0, ">", Attr.bold);
    }
}

/// factory for List(S, T)
auto list(S, T)(S curses, T screen)
{
    return new List!(S, T)(curses, screen);
}

/// Statusline
class Status(S, T)
{
    S curses;
    T screen;
    Model model;
    this(S curses, T screen)
    {
        this.curses = curses;
        this.screen = screen;
    }

    auto update(Model model)
    {
        this.model = model;
        return this;
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
auto status(S, T)(S curses, T screen)
{
    return new Status!(S, T)(curses, screen);
}

/// The ui made out of List and Status
class Ui(S, T)
{
    S curses;
    T screen;
    List!(S, T) list;
    Status!(S, T) status;
    this(S curses, T screen, List!(S, T) list, Status!(S, T) status)
    {
        this.curses = curses;
        this.screen = screen;
        this.list = list;
        this.status = status;
    }

    auto render()
    {
        screen.clear;
        list.render;
        status.render;

        screen.refresh;
        curses.update;
        return this;
    }

    auto resize()
    {
        list.resize;
        status.resize;
        return render;
    }

    auto update(Model model)
    {
        list.update(model);
        status.update(model);

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
auto ui(S, T)(S curses, T screen, List!(S, T) list, Status!(S, T) status)
{
    return new Ui!(S, T)(curses, screen, list, status);
}

void main(string[] args)
{
    string[] all;
    foreach (ulong i, string l; lines(stdin))
    {
        import std.string;

        all ~= l.strip;
    }

    import core.sys.posix.unistd;

    if (!isatty(0))
    {
        stdin.reopen("/dev/tty");
    }

    Curses.Config config = {disableEcho:
    true, initKeypad : true, cursLevel : 0};
    string result;
    {
        auto curses = new Curses(config);
        scope (exit)
            destroy(curses);

        auto screen = curses.stdscr;

        string pattern = "";
        auto matchList = list(curses, screen);
        auto status = status(curses, screen);
        auto ui = ui(curses, screen, matchList, status);

        ui.update(new Model(all, pattern));

        bool finished = false;
        while (!finished)
        {
            auto input = screen.getwch;
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
                case Key.enter:
                    finished = true;
                    result = matchList.get;
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
                    finished = true;
                    result = matchList.get;
                    break;
                case 127:
                    if (pattern.length > 0)
                    {
                        pattern = pattern[0 .. $ - 1];
                        ui.update(new Model(all, pattern));
                    }
                    break;
                default:
                    pattern ~= input.chr;
                    ui.update(new Model(all, pattern));
                    break;
                }
            }
        }
    }
    writeln(result);
}
