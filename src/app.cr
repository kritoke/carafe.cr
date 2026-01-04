require "./cli"

begin
  Carafe::CLI.run
rescue ex : OptionParser::InvalidOption
  STDERR.puts ex.message
  exit 1
rescue ex : Exception
  STDERR.puts "ERROR: #{ex.message}"
  STDERR.puts ex.backtrace.join("\n")
  exit 1
end
