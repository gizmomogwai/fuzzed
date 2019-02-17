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

auto attributed(Match match)
{
    Attr[] res;
    res.length = match.value.length;
    foreach (p; match.positions)
    {
        if (p < res.length)
        {
            res[p] = Attr.standout;
        }
    }
    return res;
}

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

class List(S, T)
{
    S curses;
    T screen;
    // selection should be between offset and offset+height
    int selection;
    int offset;
    int totalCount;
    Model model;
    int height;
    this(S curses, T screen)
    {
        this.curses = curses;
        this.screen = screen;
        this.selection = 0;
        this.offset = 0;
        this.height = screen.height - 1;
    }

    string get()
    {
        return model.matches[selection].value;
    }

    void update(Model model)
    {
        this.model = model;
        offset = 0;
        selection = 0;
    }

    void resize()
    {
        writeln("resize");
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
        }
        while (selection >= offset + height)
        {
            offset++;
        }
    }

    void selectDown()
    {
        if (selection > 0)
        {
            selection--;
        }
        while (selection < offset)
        {
            offset--;
        }
    }

    private void render()
    {
        auto matches = model.matches[offset .. min(model.matches.length, offset + height)];
        foreach (index, match; matches)
        {
            screen.addstr(height - index.to!int - 1, 2,
                    match.value[0 .. min(screen.width - 2, match.value.length)],
                    match.attributed, OOB.ignore);
        }
        screen.addstr(selectionToScreen, 0, ">");
    }
}

auto list(S, T)(S curses, T screen)
{
    return new List!(S, T)(curses, screen);
}

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

auto status(S, T)(S curses, T screen)
{
    return new Status!(S, T)(curses, screen);
}

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

    Curses.Config config;
    with (config)
    {
        disableEcho = false;
        initKeypad = true;
        cursLevel = 0;
    }
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
                if (input.chr == 13)
                {
                    finished = true;
                    result = matchList.get;
                }
                else
                {
                    pattern ~= input.chr;
                    ui.update(new Model(all, pattern));
                }
            }
        }
    }
    writeln(result);
}
