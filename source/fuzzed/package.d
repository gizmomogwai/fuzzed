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
import tui : Key, EventType, Ui, Component, Context, Terminal, KeyInput, Modifier, Refresh;
import tui.components : List, HSplit, Filled, Button;

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
            if (sw.peek > chunkDuration)
            {
                (string[] l) {
                    (cast() terminal).runInTerminalThread(() {
                        (cast() model).append(l);
                    });
                }(lines);
                lines = [];
                sw.reset();
            }
        }
        (cast() terminal).runInTerminalThread(() { (cast() model).append(lines); });
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
        reader = spawnLinked(&readerLoop, cast(shared) model, cast(shared) terminal);
    }
    else
    {
        model.setData(data);
    }
    auto list = new List!(Match, match => match.renderForList)(() => model.matches, true);
    list.setInputHandler((input) {
        if (input.key == Key.escape && input.eventType == EventType.press)
        {
            state.finished = true;
            return true;
        }
        if (input.key == Key.enter && input.eventType == EventType.press)
        {
            state.result = cast(shared(Match))(list.getSelection);
            state.finished = true;
            return true;
        }
        if (input.key == Key.backspace && (input.eventType == EventType.press
            || input.eventType == EventType.repeat))
        {
            if (state.pattern.length > 0)
            {
                state.pattern = state.pattern[0 .. $ - 1];
                model.update(state.pattern);
            }
            return true;
        }
        if (input.key == Key.normal && (input.eventType == EventType.press
            || input.eventType == EventType.repeat))
        {
            state.pattern ~= input.c;
            model.update(state.pattern);
            return true;
        }
        return false;
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
        if (input.key == Key.normal && input.c == 'c' && (input.modifiers & Modifier.ctrl) != 0)
        {
            break;
        }

        if (!input.empty)
        {
            ui.handleInput(cast() input);
        }
    }

    return state.result;
}
