module fuzzed.screen;

import deimos.ncurses;

import std.stdio;
import std.string;

struct CChar
{
    wint_t[] chars;
    chtype attr;

    this(wint_t chr, chtype attr = Attr.normal)
    {
        chars = [chr];
        this.attr = attr;
    }

    this(const wint_t[] chars, chtype attr = Attr.normal)
    {
        this.chars = chars.dup;
        this.attr = attr;
    }

    this(const string chars, chtype attr = Attr.normal)
    {
        import std.conv;

        this.chars = chars.to!(wint_t[]);
        this.attr = attr;
    }

    bool opBinary(op)(wint_t chr) if (op == "==")
    {
        return chars[0] == chr;
    }

    alias cchar this;

    cchar_t cchar() const @property
    {
        return prepChar(chars, attr);
    }
}

enum Attr : chtype
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

cchar_t prepChar(C : wint_t, A : chtype)(C ch, A attr)
{
    import core.stdc.stddef : wchar_t;

    cchar_t res;
    wchar_t[] str = [ch, 0];
    setcchar(&res, str.ptr, attr, PAIR_NUMBER(attr), null);
    return res;
}

cchar_t prepChar(C : wint_t, A : chtype)(const C[] chars, A attr)
{
    import core.stdc.stddef : wchar_t;
    import std.array;
    import std.range;

    cchar_t res;
    version (Win32)
    {
        import std.conv : wtext;

        const wchar_t[] str = (chars.take(CCHARW_MAX).wtext) ~ 0;
    }
    else
    {
        const wchar_t[] str = (chars.take(CCHARW_MAX).array) ~ 0;
    }
    /* Hmm, 'const' modifiers apparently were lost during porting the library
       from C to D.
    */
    setcchar(&res, cast(wchar_t*) str.ptr, attr, PAIR_NUMBER(attr), null);
    return res;
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

    void addch(C : wint_t, A : chtype)(C ch, A attr = Attr.normal)
    {
        bool isLowerRight = (curY == height - 1) && (curX == width - 1);
        auto toDraw = prepChar(ch, attr);
        if (deimos.ncurses.curses.wadd_wch(ptr, &toDraw) != OK && !isLowerRight)
            throw new Exception("Failed to add character '%s'", ch);
    }

    /* Coords, n, multiple attrs */
    void addstr(String, Range)(int y, int x, String str, Range attrs)
    {
        deimos.ncurses.curses.move(y, x);
        addnstr(str, attrs);
    }

    int currentX() @property
    {
        return deimos.ncurses.curses.getcurx(this.window);
    }

    int currentY() @property
    {
        return deimos.ncurses.curses.getcury(this.window);
    }

    void addch(cchar_t ch)
    {
        bool isLowerRight = (currentY == height - 1) && (currentX == width - 1);
        if (deimos.ncurses.curses.wadd_wch(this.window, &ch) != OK && !isLowerRight)
            throw new Exception("Failed to add complex character '%s'".format(ch));

    }

    void addnstr(String, Range)(String str, Range attrs)
    {
        import std.array;
        import std.conv;
        import std.range;
        import std.uni;

        foreach (gr; str.byGrapheme)
        {
            if (attrs.empty)
                break;

            auto attr = attrs.front;
            attrs.popFront;
            addch(CChar(text(gr[].array), attr));
        } /* foreach grapheme */
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
