import fuzzed : fuzzed;
import std.stdio : writeln;

/// Main entrypoint
int main()
{
    auto result = fuzzed();
    if (result)
    {
        result.value.writeln;
        return 0;
    }
    return 1;
}
