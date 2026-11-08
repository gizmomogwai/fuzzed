task :test do
  sh "dub test --config=unittest"
end

task :build do
  sh "dub build --config=fuzzed"
end

task :format do
    sh "find . -name '*.d' | xargs dfmt -i"
end

task :install do
    sh "cp out/exe/fuzzed ~/bin/"
end
task :default => [:format, :test, :build, :install]
