require "./cli"

begin
  Carafe::CLI.run
rescue ex : OptionParser::InvalidOption
  STDERR.puts ex.message
  exit 1
end
