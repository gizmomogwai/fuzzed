module fuzzed.screen;

import deimos.ncurses;
import std.algorithm;
import std.array;
import std.conv;
import std.range;
import std.range;
import std.stdio;
import std.string;
import std.uni;

enum Attributes : chtype
{
    normal = A_NORMAL,
    charText = A_CHARTEXT,
    color = A_COLOR,
    standout = A_STANDOUT,
    underline = A_UNDERLINE,
    reverse = A_REVERSE,
    blink = A_BLINK,
    dim = A_DIM,
    bold = A_BOLD,
    altCharSet = A_ALTCHARSET,
    invis = A_INVIS,
    protect = A_PROTECT,
    horizontal = A_HORIZONTAL,
    left = A_LEFT,
    low = A_LOW,
    right = A_RIGHT,
    top = A_TOP,
    vertical = A_VERTICAL,
}

void activate(Attributes attributes)
{
    (attributes & Attributes.bold) ? deimos.ncurses.curses.attron(A_BOLD)
        : deimos.ncurses.curses.attroff(A_BOLD);
    (attributes & Attributes.reverse) ? deimos.ncurses.curses.attron(A_REVERSE)
        : deimos.ncurses.curses.attroff(A_REVERSE);
    (attributes & Attributes.standout) ? deimos.ncurses.curses.attron(A_STANDOUT)
        : deimos.ncurses.curses.attroff(A_STANDOUT);
    (attributes & Attributes.underline) ? deimos.ncurses.curses.attron(A_UNDERLINE)
        : deimos.ncurses.curses.attroff(A_UNDERLINE);
}

/// either a special key like arrow or backspace
/// or an utf-8 string (e.g. ä is already 2 bytes in an utf-8 string)
struct KeyInput
{
    bool specialKey;
    wint_t key;
    string input;
    this(bool specialKey, wint_t key, string input)
    {
        this.specialKey = specialKey;
        this.key = key;
        this.input = input.dup;
    }

    static KeyInput fromSpecialKey(wint_t key)
    {
        return KeyInput(true, key, "");
    }

    static KeyInput fromText(string s)
    {
        return KeyInput(false, 0, s);
    }
}

class NoKeyException : Exception
{
    this(string s)
    {
        super(s);
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

    ~this()
    {
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

    auto addstring(int y, int x, string text)
    {
        deimos.ncurses.curses.move(y, x);
        deimos.ncurses.curses.addstr(text.toStringz);
        return this;
    }

    auto addstring(Range)(int y, int x, Range str)
    {
        deimos.ncurses.curses.move(y, x);
        addstring(str);
        return this;
    }

    void addstring(Range)(Range str)
    {
        foreach (grapheme, attribute; str)
        {
            attribute.activate;
            deimos.ncurses.curses.addstr(text(grapheme[]).toStringz);
            deimos.ncurses.curses.attrset(A_NORMAL);
        }
    }

    int currentX() @property
    {
        return deimos.ncurses.curses.getcurx(this.window);
    }

    int currentY() @property
    {
        return deimos.ncurses.curses.getcury(this.window);
    }

    auto getWideCharacter()
    {
        wint_t key1;
        int res = wget_wch(this.window, &key1);
        switch (res)
        {
        case KEY_CODE_YES:
            return KeyInput.fromSpecialKey(key1);
        case OK:
            return KeyInput.fromText(key1.to!string);
        default:
            throw new NoKeyException("Could not read a wide character");
        }
    }
}

int byteCount(int k)
{
    if (k < 0b1100_0000)
    {
        return 1;
    }
    if (k < 0b1110_0000)
    {
        return 2;
    }

    if (k > 0b1111_0000)
    {
        return 3;
    }

    return 4;
}

@("test strings") unittest
{
    string s = ['d'];
    writeln(KeyInput.fromText(s));
    import std.stdio;

    writeln(s.length);
}
