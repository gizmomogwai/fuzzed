task :test do
  sh "dub test"
end

task :build do
  sh "dub build -c fuzzed"
end

task :default => [:test, :build]

