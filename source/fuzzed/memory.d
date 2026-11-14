module fuzzed.memory;

import std.algorithm : all, max;
import std.conv : ConvException, octal, to;
import std.exception : enforce;
import std.file : exists, FileException, mkdirRecurse, read, setAttributes;
import std.path : buildPath, dirName;
import std.process : environment;
import std.stdio : File, stderr, StdioException;
import std.string : empty, indexOf, representation, split;

private class SelectionMemoryException : Exception
{
    this(string message, string file = __FILE__, size_t line = __LINE__, Throwable cause = null)
    {
        super(message, file, line, cause);
    }
}

/// Exact candidate strings and their accepted selection counts.
final class SelectionMemory
{
    private string path;
    private ulong[string] counts;

    /// best effort loading of the past selection counts
    this(string path = null)
    {
        this.path = path.length ? path : defaultPath();
        counts = load();
    }

    ulong selectionCount(string entry) const
    {
        const stored = entry in counts;
        return stored is null ? 0 : *stored;
    }

    /// best effort recording of a selection
    void recordSelection(string entry, ulong selectionCount)
    {
        try
        {
            enforce!SelectionMemoryException(entry.indexOf('\n') < 0
                    && entry.indexOf('\r') < 0, "Cannot remember an entry containing a line break");
            counts[entry] = selectionCount + 1;
            save(counts);
        }
        catch (Exception failure)
        {
            reportFailure("update", failure);
        }
    }

    private static void reportFailure(string operation, Exception failure)
    {
        stderr.writeln("fuzzed: cannot ", operation, " memory: ", failure);
        for (auto cause = failure.next; cause !is null; cause = cause.next)
        {
            stderr.writeln("Caused by: ", cause);
        }
    }

    private static string defaultPath()
    {
        auto directory = environment.get("XDG_CACHE_HOME", "");
        if (directory.length == 0)
        {
            auto home = environment.get("HOME", "");
            enforce!SelectionMemoryException(home.length != 0,
                    "HOME is unset and XDG_CACHE_HOME is empty");
            directory = buildPath(home, ".cache");
        }
        return buildPath(directory, "fuzzed", "memory.log");
    }

    private ulong[string] load()
    {
        try
        {
            return readCounts();
        }
        catch (Exception failure)
        {
            reportFailure("load", failure);
        }
        return null;
    }

    private ulong[string] readCounts()
    {
        ulong[string] result;
        if (!path.exists)
        {
            return result;
        }
        auto records = (cast(string) path.read).split("\n");
        foreach (record; records)
        {
            if (record.empty)
            {
                continue;
            }
            // duplicate entries should not happen ...
            const separator = record.indexOf('|');
            (separator > 0).enforce("Cannot find separator in " ~ record);
            result[record[separator + 1 .. $]] = record[0 .. separator].to!ulong;
        }
        return result;
    }

    private void save(ulong[string] latest)
    {
        auto directory = path.dirName;
        if (!directory.exists)
        {
            directory.mkdirRecurse();
            directory.setAttributes(octal!"700");
        }
        auto output = File(path, "w");
        path.setAttributes(octal!"600");
        foreach (entry, count; latest)
        {
            output.writeln(count, "|", entry);
        }
        output.close();
    }
}
