import unit_threaded;

// dfmt off
mixin runTestsMain!(
  "fuzzed.algorithm",
  "fuzzed.model",
  "fuzzed",
);
// dfmt on
