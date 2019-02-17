task :test do
  sh "dub test"
end

task :build do
  sh "dub build -c fuzzed"
end

task :format do
    sh "find . -name '*.d' | xargs dfmt -i"
end

task :default => [:format, :test, :build]

