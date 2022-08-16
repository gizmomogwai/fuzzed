import fuzzed : StatusInfo, Match;
import fuzzed.model : modelLoop, Matches, Pattern;

import colored : reverse, underlined;
import std.algorithm : map, min, canFind;
import std.concurrency : spawnLinked, Tid, send, thisTid, receive, LinkTerminated;
import std.conv : to;
import std.format : format;
import std.range : zip, take;
import std.stdio : stdin, lines, File, writeln;
import std.string : strip;
import std.uni : byGrapheme;
import tui : Ui, Component, Context, Terminal, KeyInput, List, HSplit, Filled, Button, Refresh;
import std.format : format;
import std.file : append; // debug
import std.variant : Variant;
import std.array : array;

auto render(immutable(Match) m)
{
    string result = "";
    auto graphemes = m.value.byGrapheme;
    size_t idx = 0;
    foreach (grapheme; graphemes)
    {
        if (m.positions.canFind(idx++))
        {
            result ~= grapheme[].array.to!string.underlined.to!string;
        }
        else
        {
            result ~= grapheme[].array.to!string;
        }
    }
    return result;
}
/// Produce a range of graphemes and attributes for those
auto attributes(string s, immutable ulong[] highlights, bool selected, int offset = 0)
{
    string result = "";
    auto graphemes = s.byGrapheme;
    size_t idx = 0;
    foreach (grapheme; graphemes)
    {
        if (selected)
        {
            if (highlights.canFind(idx+offset))
            {
                result ~= grapheme.to!string.reverse.underlined.to!string;
            } else
            {
                result ~= grapheme.to!string.reverse.to!string;
            }
        } else {
            if (highlights.canFind(idx+offset))
            {
                result ~= grapheme.to!string.underlined.to!string;
            } else
            {
                result ~= grapheme.to!string;
            }
        }
        idx++;
    }
    return result.to!string;
}

class StatusInfoUi : Component
{
    Tid model;
    this(Tid model)
    {
        this.model = model;
    }
    override void render(Context context)
    {
        model.send(StatusInfo.Request(thisTid));
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
        return true;
    }

}

/// State of the search
shared class State
{
    bool finished;
    string result;
    string pattern;
}

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
    }
}

shared class Wrapper
{
    File o;
    this(File o)
    {
        this.o = cast(shared)o;
    }

    ubyte[] read(ubyte[] buffer)
    {
        return (cast() o).rawRead(buffer);
    }
}

struct InputHandlingDone
{
}
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
              "log.log".append("got key input 1\n");
              ui.handleInput(cast()input);
              "log.log".append("got key input 2\n");
              backChannel.send(InputHandlingDone());
              "log.log".append("got key input 3\n");
          },
          (Refresh refresh)
          {
              "log.log".append("got refresh event\n");
              ui.render;
          },
          (shared void delegate() codeForRenderLoop)
          {
              codeForRenderLoop();
          },
          (Variant v)
          {
              "log.log".append("got variant: ");
              "log.log".append(v.to!string);
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
    "log.log".append("renderloop finished\n");
    } catch (Exception e) {
        "log.log".append("\n\n!!!!!!!!!!!\nrenderloop with exception %s\n".format(e.to!string));
    }
}
// reader loop:
//   - reads stdin and processes it, then forwards to the modelloop
// modelloop:
//   - integrates reader loop data into the model
//   - can return data for the render thread to render
// renderloop:
//   - holds application state (via FuzzedUi : Ui)
//   - sits there and waits for events then renders
//   - keyinput (from the mainthread) triggers an event
//   - model changes trigger a refresh event
// mainthread:
//   - reads keyevents blocking
/// the main
void myLoop(State s)
{
    renderLoop!State(s);
}

void main(string[] args)
{
    shared w = new Wrapper(stdin);
    KeyInput keyInput;
    auto state = new State();
    {
    scope terminal = new Terminal();

    import core.stdc.locale;

    setlocale(LC_ALL, "");


    auto renderer = spawnLinked(&myLoop, state);
    auto model = spawnLinked(&modelLoop, renderer);
    auto reader = spawnLinked(&readerLoop, w, model);

    auto list = new List!(immutable(Match),
        match => match.render)(
          () {
            model.send(Matches.Request(thisTid));
            immutable(Match)[] result;
            receive(
              (Matches matches)
              {
                  result = matches.matches;
              },
            );
            return result;
        });
    list.setInputHandler((input) {
            if (input.input == "\n")
            {
                "log.log".append("Return pressed\n");
                state.result = list.getSelection.value;
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
            "log.log".append("read input: %s\n".format(input));
            renderer.send(thisTid, input);
            bool done = false;
            while (!done) {
            receive(
              (InputHandlingDone inputHandlingDone) {
                  "log.log".append("input handled ... continueing\n");
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
        stdin.close;
    }

    }
    if (state.result)
    {
        state.result.writeln;
    }
}
