import unit_threaded;

// dfmt off
mixin runTestsMain!(
  "fuzzed",
  "fuzzed.algorithm",
  "fuzzed.model",
);
// dfmt on
