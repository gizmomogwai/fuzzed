import fuzzed;

import colored;
import deimos.ncurses;
import std.algorithm;
import std.array;
import std.concurrency;
import std.conv;
import std.format;
import std.range;
import std.stdio;
import std.string;

/// Produce ncurses attributes array for a stringish thing with highlights and selection style
/*
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
*/
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
struct Input
{
    int i;
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
          (Input input)
          {   model.append("%s".format(input.i));
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
class UiList(S)
{
    S screen;
    int height;
    Details details;

    Tid model;
    immutable(Match)[] allMatches;

    this(S screen, Tid model)
    {
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
        // dfmt off
        auto matches = allMatches[
          min(allMatches.length, details.offset) .. min(allMatches.length, details.offset + height)];
        // dfmt on
        foreach (index, match; matches)
        {
            auto y = height - index.to!int - 1;
            bool selected = index == details.selection - details.offset;
            auto text = (selected ? "> %s" : "  %s").format(match.value)
                .take(screen.width).to!string;
            screen.addstr(y, 0, text); //, text.attributes(match.positions, selected, 2), OOB.ignore);
        }
    }
}

/// factory for List(S)
auto uiList(S)(S screen, Tid model)
{
    return new UiList!(S)(screen, model);
}

/// Statusline
class UiStatus(S)
{
    S screen;
    Tid model;
    Details details;
    this(S screen, Tid model, Details details)
    {
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
        // dfmt off
        receive(
          (StatusInfo response)
          {
              statusInfo = response;
          },
        );
        // dfmt on

        auto matches = statusInfo.matches;
        auto all = statusInfo.all;
        auto pattern = statusInfo.pattern;

        auto trimmedCounter = "%s/%s (selection %s/offset %s)".format(details.matches,
                                                                      details.total, details.selection, details.offset).take(screen.width - 2).to!string;
        screen.addstr(screen.height - 2, 2, trimmedCounter);

        auto trimmedPattern = "> %s".format(pattern).take(screen.width - 2).to!string;
        screen.addstr(screen.height - 1, 0, trimmedPattern); //.attributes([], true));
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

/// factory for Status(S)
auto uiStatus(S)(S screen, Tid model, Details details)
{
    return new UiStatus!(S)(screen, model, details);
}

/// The ui made out of List and Status
class Ui(S)
{
    S screen;
    UiList!(S) list;
    UiStatus!(S) status;
    this(S screen, Tid model)
    {
        this.screen = screen;
        this.list = uiList(screen, model);
        this.status = uiStatus(screen, model, this.list.details);
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
            screen.update;

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

/// factory for UI(S)
auto ui(S)(S screen, Tid model)
{
    return new Ui!(S)(screen, model);
}

/// State of the search
struct State
{
    bool finished;
    string result;
    string pattern;
}

enum Key : int
{
    codeYes = KEY_CODE_YES,
        min = KEY_MIN,
        codeBreak = KEY_BREAK, /* This should've been just 'break', but that's a
                                  keyword. */

        down = KEY_DOWN,
        up = KEY_UP,
        left = KEY_LEFT,
        right = KEY_RIGHT,
        home = KEY_HOME,
        backspace = KEY_BACKSPACE,
        f0 = KEY_F0,
        f1 = KEY_F(1),
        f2 = KEY_F(2),
        f3 = KEY_F(3),
        f4 = KEY_F(4),
        f5 = KEY_F(5),
        f6 = KEY_F(6),
        f7 = KEY_F(7),
        f8 = KEY_F(8),
        f9 = KEY_F(9),
        f10 = KEY_F(10),
        f11 = KEY_F(11),
        f12 = KEY_F(12),
        f13 = KEY_F(13),
        f14 = KEY_F(14),
        f15 = KEY_F(15),
        f16 = KEY_F(16),
        f17 = KEY_F(17),
        f18 = KEY_F(18),
        f19 = KEY_F(19),
        f20 = KEY_F(20),
        f21 = KEY_F(21),
        f22 = KEY_F(22),
        f23 = KEY_F(23),
        f24 = KEY_F(24),
        f25 = KEY_F(25),
        f26 = KEY_F(26),
        f27 = KEY_F(27),
        f28 = KEY_F(28),
        f29 = KEY_F(29),
        f30 = KEY_F(30),
        f31 = KEY_F(31),
        f32 = KEY_F(32),
        f33 = KEY_F(33),
        f34 = KEY_F(34),
        f35 = KEY_F(35),
        f36 = KEY_F(36),
        f37 = KEY_F(37),
        f38 = KEY_F(38),
        f39 = KEY_F(39),
        f40 = KEY_F(40),
        f41 = KEY_F(41),
        f42 = KEY_F(42),
        f43 = KEY_F(43),
        f44 = KEY_F(44),
        f45 = KEY_F(45),
        f46 = KEY_F(46),
        f47 = KEY_F(47),
        f48 = KEY_F(48),
        f49 = KEY_F(49),
        f50 = KEY_F(50),
        f51 = KEY_F(51),
        f52 = KEY_F(52),
        f53 = KEY_F(53),
        f54 = KEY_F(54),
        f55 = KEY_F(55),
        f56 = KEY_F(56),
        f57 = KEY_F(57),
        f58 = KEY_F(58),
        f59 = KEY_F(59),
        f60 = KEY_F(60),
        f61 = KEY_F(61),
        f62 = KEY_F(62),
        f63 = KEY_F(63),
        dl = KEY_DL,
        il = KEY_IL,
        dc = KEY_DC,
        ic = KEY_IC,
        eic = KEY_EIC,
        clear = KEY_CLEAR,
        eos = KEY_EOS,
        eol = KEY_EOL,
        sf = KEY_SF,
        sr = KEY_SR,
        npage = KEY_NPAGE,
        ppage = KEY_PPAGE,
        stab = KEY_STAB,
        ctab = KEY_CTAB,
        catab = KEY_CATAB,
        enter = KEY_ENTER,
        sreset = KEY_SRESET,
        reset = KEY_RESET,
        print = KEY_PRINT,
        ll = KEY_LL,
        a1 = KEY_A1,
        a3 = KEY_A3,
        b2 = KEY_B2,
        c1 = KEY_C1,
        c3 = KEY_C3,
        btab = KEY_BTAB,
        beg = KEY_BEG,
        cancel = KEY_CANCEL,
        close = KEY_CLOSE,
        command = KEY_COMMAND,
        copy = KEY_COPY,
        create = KEY_CREATE,
        end = KEY_END,
        exit = KEY_EXIT,
        find = KEY_FIND,
        help = KEY_HELP,
        mark = KEY_MARK,
        message = KEY_MESSAGE,
        move = KEY_MOVE,
        next = KEY_NEXT,
        open = KEY_OPEN,
        options = KEY_OPTIONS,
        previous = KEY_PREVIOUS,
        redo = KEY_REDO,
        reference = KEY_REFERENCE,
        refresh = KEY_REFRESH,
        replace = KEY_REPLACE,
        restart = KEY_RESTART,
        resume = KEY_RESUME,
        save = KEY_SAVE,
        sbeg = KEY_SBEG,
        scancel = KEY_SCANCEL,
        scommand = KEY_SCOMMAND,
        scopy = KEY_SCOPY,
        screate = KEY_SCREATE,
        sdc = KEY_SDC,
        sdl = KEY_SDL,
        select = KEY_SELECT,
        send = KEY_SEND,
        seol = KEY_SEOL,
        sexit = KEY_SEXIT,
        sfind = KEY_SFIND,
        shelp = KEY_SHELP,
        shome = KEY_SHOME,
        sic = KEY_SIC,
        sleft = KEY_SLEFT,
        smessage = KEY_SMESSAGE,
        smove = KEY_SMOVE,
        snext = KEY_SNEXT,
        soptions = KEY_SOPTIONS,
        sprevious = KEY_SPREVIOUS,
        sprint = KEY_SPRINT,
        sredo = KEY_SREDO,
        sreplace = KEY_SREPLACE,
        sright = KEY_SRIGHT,
        srsume = KEY_SRSUME,
        ssave = KEY_SSAVE,
        ssuspend = KEY_SSUSPEND,
        sundo = KEY_SUNDO,
        suspend = KEY_SUSPEND,
        undo = KEY_UNDO,
        mouse = KEY_MOUSE,
        resize = KEY_RESIZE,
        event = KEY_EVENT,
        max = KEY_MAX,
        }

/// handle input events
State handleKey(S, T)(S input, T ui, Tid model, State state)
{
      if (input.specialKey)
      {
          switch (input.character)
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
          model.send(Input(input.character));
          switch (input.character)
          {
          case 10:
              state.finished = true;
              state.result = ui.get;
              break;
          case 127:
              if (state.pattern.length > 0)
              {
                  state.pattern = state.pattern[0 .. $ - 1];
                  model.send(Pattern(state.pattern.idup));
              }
              break;
          default:
              state.pattern ~= input.character;
              model.send(Pattern(state.pattern.idup));
              break;
          }
      }
    return state;
}

import std.stdio;

void readerLoop(shared Wrapper input, Tid model)
{
    try
    {
        foreach (string line; lines((cast() input).o))
        {
            model.send(line.strip.idup);
        }
    }
    catch (Exception e)
    {
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

class Screen
{
    File tty;
    SCREEN* screen;
    WINDOW* window;
    this(string file)
    {
        this.tty = File("/dev/tty", "r+");
        this.screen = newterm(null, tty.getFP, tty.getFP);
        this.screen.set_term;
        this.window = stdscr;
        deimos.ncurses.curses.noecho;
        deimos.ncurses.curses.halfdelay(1);
        deimos.ncurses.curses.keypad(this.window, true);
        deimos.ncurses.curses.curs_set(0);
        deimos.ncurses.curses.wtimeout(this.window, 50);
    }
    ~this() {
        deimos.ncurses.curses.endwin;
        this.screen.delscreen;
    }
    auto clear()
    {
        int res = nclear;
        // todo error handling
        return this;
    }

    auto refresh()
    {
        deimos.ncurses.curses.refresh;
        // todo error handling
        return this;
    }

    auto update()
    {
        deimos.ncurses.curses.doupdate;
        // todo error handling
        return this;
    }

    int width() @property
    {
        return deimos.ncurses.curses.getmaxx(this.window) + 1;
    }

    int height() @property
    {
        return deimos.ncurses.curses.getmaxy(this.window) + 1;
    }

    auto addstr(int y, int x, string text)
    {
        deimos.ncurses.curses.move(y, x);
        deimos.ncurses.curses.addstr(text.toStringz);
        return this;
    }

    auto getwch()
    {
        wint_t key;
        int res = wget_wch(this.window, &key);
        switch (res)
        {
        case KEY_CODE_YES:
            return WideCharacter(key, true);
        case OK:
            return WideCharacter(key, false);
        default:
            throw new Exception("Failed to get a wide character");
        }
    }
}

struct WideCharacter
{
    wint_t character;
    bool specialKey;
    this(wint_t character, bool specialKey)
    {
        this.character = character;
        this.specialKey = specialKey;
    }
}

/+
void testmain(string[] args) {
     initialize curses on fresh tty
     auto tty = File("/dev/tty", "r+");
     auto screen = newterm(null, tty.getFP, tty.getFP);
     screen.set_term;
     scope (exit) {
         endwin;
         screen.delscreen;
         "over and out".writeln;
     }
     immutable hello = toStringz("Hello ncurses World!\nPress any key to continue...");
     printw(hello); // prints the char[] hello to the screen
     refresh();     // actually does the writing to the physical screen
     getch();
     }
 +/
/// the main
void main(string[] args)
{

    import core.sys.posix.unistd;
    import std.stdio;

    shared w = cast(shared)(new Wrapper(stdin));

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
    Screen screen = new Screen("/dev/tty");

    auto ui = ui(screen, model);
    ui.render;
    while (!state.finished)
    {
        try {
            auto input = screen.getwch;
            state = handleKey(input, ui, model, state);
            ui.render;
        } catch (Exception e) {
        }
    }
    screen.destroy;

    if (state.result)
    {
        writeln(state.result);
    }
}
