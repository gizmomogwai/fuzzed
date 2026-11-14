import unit_threaded;

// dfmt off
mixin runTestsMain!(
  "fuzzed",
  "fuzzed.algorithm",
  "fuzzed.memory",
  "fuzzed.model",
);
// dfmt on
