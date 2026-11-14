import argparse : Command, Description, NamedArgument, Optional, PositionalArgument;
import argparse.api.cli : CLI;
import fuzzed : fuzzed;
import fuzzed.memory : SelectionMemory;
import std.algorithm : countUntil;
import std.stdio : writeln;

@(Command("fuzzed").Description("Filter candidates interactively, like fzf. "
        ~ "Read lines from stdin when no candidates are given."))
private struct Arguments
{
    @(NamedArgument.Description(
            "Remember accepted candidates and rank by usage (true|false; default: true)"))
    bool memory = true;
    @(PositionalArgument(0).Optional().Description("Candidates to filter"))
    string[] candidates;
}

private int run(Arguments options)
{
    auto memory = options.memory ? new SelectionMemory() : null;
    auto result = fuzzed(options.candidates, memory);
    if (result !is null)
    {
        if (memory !is null)
        {
            memory.recordSelection(result.value, result.selectionCount);
        }
        result.value.writeln;
        return 0;
    }
    return 1;
}

mixin CLI!Arguments.main!((arguments) { return run(arguments); });
