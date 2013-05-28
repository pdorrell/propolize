require 'erb'
require 'propolize'

if ARGV.length == 0
  mainNoArgs
elsif ARGV.length == 3
  propolizeFile(ARGV[0], ARGV[1], ARGV[2])
else
  raise Exception, "Wrong number of args (either 0 or 3) : #{ARGS.inspect}"
end

