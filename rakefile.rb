task :test do
  sh "dub test"
end

task :build do
  sh "dub build -c fuzzed"
end

task :format do
    sh "find . -name '*.d' | xargs dfmt -i"
end

task :install do
    sh "cp out/exe/fuzzed ~/bin/"
end
task :default => [:format, :test, :build, :install]

