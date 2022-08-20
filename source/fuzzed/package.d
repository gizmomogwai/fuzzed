module fuzzed;

import colored : reverse, underlined, forceStyle;
import fuzzed.algorithm : Match;
import fuzzed.model : modelLoop, Matches, Pattern, StatusInfo;
import std.algorithm : map, min, canFind;
import std.array : array;
import std.concurrency : spawnLinked, Tid, send, thisTid, receive, LinkTerminated;
import std.conv : to;
import std.file : append; // debug
import std.format : format;
import std.format : format;
import std.range : take;
import std.stdio : stdin, lines, File;
import std.string : strip;
import std.uni : byGrapheme;
import std.variant : Variant;
import tui : Ui, Component, Context, Terminal, KeyInput, List, HSplit, Filled, Button, Refresh;

/// Underlines the matched parts of the value of a match
auto renderForList(immutable(Match) m)
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

/++ Two lines status info (matchinfo and current search attern)
 + Works with an asyn model
 +/
class StatusInfoUi : Component
{
    Tid model;
    this(Tid model)
    {
        this.model = model;
    }

    override void render(Context context)
    {
        model.send(thisTid, StatusInfo.Request());
        StatusInfo statusInfo;
        // dfmt off
        receive(
            (StatusInfo response)
            {
                statusInfo = response;
            },
        );
        auto matches = statusInfo.matches;
        auto all = statusInfo.all;
        auto pattern = statusInfo.pattern;

        auto counter = "%s/%s"/* (selection %s/offset %s)"*/.format(statusInfo.matches, statusInfo.all).to!string;
        context.putString(2, 0, counter);

        auto line = "> %s".format(pattern).to!string;
        context.putString(0, 1, line);
    }
    override bool focusable() {
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

/++ loop to read in all the dat afrom stdin and send it to the model
 + supposed to be spawned
 +/
void readerLoop(Wrapper input, Tid model)
{
    try
    {
        foreach (string line; lines(cast()(input.o)))
        {
            model.send(line.strip.idup);
        }
    }
    catch (Exception e)
    {
        "log.log".append("readerLoop %s".format(e.to!string));
    }
}

/// Dirty workaround to get stdin from a to b
shared class Wrapper
{
    File o;
    this(File o)
    {
        this.o = cast(shared)o;
    }
}


/// Signals that the KeyInput processing is done
struct InputHandlingDone
{
}

/// Generic render loop
void renderLoop(S)(S state)
{
    try {
        Ui ui = null;
        while (true) {
            receive(
                (shared(Ui) newUi)
                {
                    ui = cast()newUi;
                },
                (Tid backChannel, immutable(KeyInput) input)
                {
                    ui.handleInput(cast()input);
                    backChannel.send(InputHandlingDone());
                },
                (Refresh refresh)
                {
                    if (ui !is null)
                    {
                        ui.render;
                    }
                },
                (shared void delegate() codeForRenderLoop)
                {
                    codeForRenderLoop();
                },
                (Variant v)
                {
                    "log.log".append("renderloop-got variant: %s\n".format(v.to!string));
                },
            );
            if (state.finished)
            {
                break;
            }
            if (ui !is null)
            {
                ui.render;
            }
        }
    } catch (Exception e) {
        "log.log".append("renderloop with exception %s\n".format(e.to!string));
    }
}

/// helper for spawning "our" parametrized renderloop
void myLoop(State s)
{
    renderLoop!State(s);
}

/// mess around with locale
private void setLocale()
{
    import core.stdc.locale;
    setlocale(LC_ALL, "");
}

auto fuzzed(string[] data=null)
{
    auto state = new State();
    bool raiseSigInt = false;
    {
        KeyInput keyInput;
        scope terminal = new Terminal();

        setLocale();

        auto renderer = spawnLinked(&myLoop, state);
        auto model = spawnLinked(&modelLoop, renderer);
        if (data != null)
        {
            foreach (s; data)
            {
                model.send(s);
            }
        }
        else
        {
            auto w = new Wrapper(stdin);
            auto reader = spawnLinked(&readerLoop, w, model);
        }
        auto list = new List!(immutable(Match), match => match.renderForList)
            (() {
                model.send(thisTid, Matches.Request());
                immutable(Match)[] result;
                receive(
                  (Matches matches)
                  {
                      result = matches.matches;
                  },
                );
                return result;
            });
        list.setInputHandler(
            (input) {
                if (input.input == "\x1B")
                {
                    raiseSigInt = true;
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
                        state.pattern = state.pattern[0..$-1];
                        model.send(Pattern(state.pattern));
                    }
                    return true;
                }
                renderer.send(cast(shared)() {
                        state.pattern ~= input.input;
                        model.send(Pattern(state.pattern));
                    });
                return true;
            });

        auto statusInfo = new StatusInfoUi(model);
        auto root = new HSplit(-2, list, statusInfo);

        auto ui= new Ui(terminal);
        ui.push(root);
        ui.resize();
        renderer.send(cast(shared)ui);
        {
            while (!state.finished)
            {
                immutable input = terminal.getInput;
                renderer.send(thisTid, input);
                bool done = false;
                while (!done) {
                    receive(
                      (InputHandlingDone inputHandlingDone) {
                          done = true;
                      },
                      (LinkTerminated linkTerminated)
                      {
                          // ignore for now (e.g. reader also sends link terminated)
                      },
                      (Variant v) {
                          "log.log".append("received variant:%s\n".format(v.to!string));
                      },
                    );
                }
            }
        }
    }
    if (raiseSigInt)
    {
        import core.stdc.signal : raise, SIGINT;
        raise(SIGINT);
    }
    return cast()(state.result);
}
