module fuzzed;

import colored : reverse, underlined, forceStyle;
import core.stdc.signal : raise, SIGINT;
import fuzzed.algorithm : Match;
import fuzzed.model : Model, Matches, Pattern, StatusInfo;
import std.algorithm : map, min, canFind;
import std.array : array;
import std.concurrency : spawnLinked, Tid, send, thisTid, receive;
import std.conv : to;
import std.format : format;
import std.range : take;
import std.stdio : stdin, lines, File, writeln;
import std.string : strip;
import std.uni : byGrapheme;
import std.variant : Variant;
import tui : Ui, Component, Context, Terminal, KeyInput, List, HSplit, Filled, Button, Refresh;

/// Underlines the matched parts of the value of a match
auto renderForList(Match m)
{
    auto result = "";
    auto graphemes = m.value.byGrapheme;
    size_t idx = 0;
    foreach (grapheme; graphemes)
    {
        if (m.positions.canFind(idx++))
        {
            result ~= grapheme[].array
                .to!string
                .underlined
                .to!string;
        }
        else
        {
            result ~= grapheme[].array.to!string;
        }
    }
    return result;
}

/++ Two lines status info (matchinfo and current search pattern)
 + Works with an async model
 +/
class StatusInfoUi : Component
{
    Model model;
    this(Model model)
    {
        this.model = model;
    }

    override void render(Context context)
    {
        auto matches = model.matches.length;
        auto all = model.all.length;
        auto pattern = model.pattern;

        auto counter = format("%s/%s", matches, all);
        context.putString(2, 0, counter);

        auto line = format!("> %s")(pattern);
        context.putString(0, 1, line);
    }

    override bool focusable()
    {
        return false;
    }
}

/// State of the application
shared class State
{
    /// true if the application is done
    bool finished;
    /// the resulting selection
    Match result;
    /// the current search pattern
    string pattern;
}

/++ loop to read in all the data from stdin and send it to the model
 + supposed to be spawned
 +/
void readerLoop(shared(Model) model, shared(Terminal) terminal)
{
    try
    {
        import std.datetime.stopwatch : msecs, StopWatch, AutoStart;
        auto chunkDuration = 200.msecs;
        auto sw = StopWatch(AutoStart.yes);
        string[] lines;
        foreach (line; stdin.byLineCopy)
        {
            lines ~= line;
            if (sw.peek > chunkDuration) {
                (cast()terminal).runInTerminalThread((lines){return() => (cast()model).append(lines); }(lines));
                lines = [];
                sw.reset();
            }
        }
        (cast()terminal).runInTerminalThread((lines){return() => (cast()model).append(lines); }(lines));
    }
    catch (Exception e)
    {
    }
}

/// mess around with locale
private void setLocale()
{
    import core.stdc.locale;

    setlocale(LC_ALL, "");
}

State state = new State();

auto setupFDs()
{
    import core.sys.posix.fcntl : O_RDWR, open;
    import core.sys.posix.unistd : isatty;
    import std.typecons : tuple;

    int stdinFD = 0;
    int stdoutFD = 1;
    if (!isatty(0))
    {
        int tty = open("/dev/tty", O_RDWR);
        stdinFD = tty;
    }
    return tuple!("inFD", "outFD")(stdinFD, stdoutFD);
}

auto fuzzed(string[] data = null)
{
    KeyInput keyInput;
    auto fds = setupFDs();
    scope terminal = new Terminal(fds.inFD, fds.outFD);
    setLocale();
    Tid reader;
    auto model = new Model();
    if (data is null)
    {
        reader = spawnLinked(&readerLoop, cast(shared)model, cast(shared)terminal);
    }
    else
    {
        model.setData(data);
    }
    auto list = new List!(Match, match => match.renderForList)(() => model.matches, true);
    list.setInputHandler((input) {
        if (input.input == "\x1B") // escape key
        {
            state.finished = true;
            return true;
        }
        if (input.input == "\n")
        {
            state.result = cast(shared(Match))(list.getSelection);
            state.finished = true;
            return true;
        }
        if (input.input == "\x7F")
        {
            if (state.pattern.length > 0)
            {
                state.pattern = state.pattern[0 .. $ - 1];
                model.update(state.pattern);
            }
            return true;
        }
        state.pattern ~= input.input;
        model.update(state.pattern);
        return true;
    });

    auto statusInfo = new StatusInfoUi(model);
    auto root = new HSplit(-2, list, statusInfo);

    auto ui = new Ui(terminal);
    ui.push(root);

    ui.resize();
    while (!state.finished)
    {
        ui.render;
        auto input = terminal.getInput;
        if (input.ctrlC)
        {
            break;
        }
        if (!input.empty)
        {
            ui.handleInput(cast()input);
        }
    }

    return state.result;
}
