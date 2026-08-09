require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "lib"
  t.pattern = "test/**/*_test.rb"
  t.warning = true
end

task default: :test
