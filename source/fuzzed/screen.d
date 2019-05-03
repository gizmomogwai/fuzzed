module fuzzed.screen;

import deimos.ncurses;
import std.array;
import std.conv;
import std.range;

import std.stdio;
import std.string;
import std.uni;
import std.algorithm;
import std.range;

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
    if (attributes & Attributes.bold)
    {
        attron(A_BOLD);
    }
    else
    {
        attroff(A_BOLD);
    }
    if (attributes & Attributes.reverse)
    {
        attron(A_REVERSE);
    }
    else
    {
        attroff(A_REVERSE);
    }
    if (attributes & Attributes.standout)
    {
        attron(A_STANDOUT);
    }
    else
    {
        attroff(A_STANDOUT);
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

    auto addstr(int y, int x, string text)
    {
        deimos.ncurses.curses.move(y, x);
        deimos.ncurses.curses.addstr(text.toStringz);
        return this;
    }

    void addstr(Range)(int y, int x, string str, Range attributes)
    {
        deimos.ncurses.curses.move(y, x);
        addstr(str, attributes);
    }

    void addstr(string str, Attributes[] attributes)
    {
        foreach (c, attr; zip(str.byGrapheme.array, attributes))
        {
            attr.activate;
            deimos.ncurses.curses.addstr(text(c[].array).toStringz);
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
