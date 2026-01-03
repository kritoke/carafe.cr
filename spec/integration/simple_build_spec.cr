require "spec"
require "../support/tempfile"
require "../../src/site"
require "../../src/builder"

describe "simple build spec" do
  it "builds" do
    site = Carafe::Site.new("spec/fixtures/simple-site")

    site.run_generators

    with_tempdir("simple_build") do |output_path|
      site.config.destination = output_path
      builder = Carafe::Builder.new(site)
      builder.build

      output = IO::Memory.new
      Process.run("diff", ["-r", "spec/fixtures/simple-site/_build", output_path], output: output, error: STDERR)
      output.to_s.should be_empty
    end
  end
end
