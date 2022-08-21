import fuzzed : fuzzed;
import std.stdio : writeln;

/// Main entrypoint
int main(string[] args)
{
    auto strippedArgs = args.length > 1 ? args[1 .. $] : null;
    auto result = fuzzed(strippedArgs);
    if (result)
    {
        result.value.writeln;
        return 0;
    }
    return 1;
}
