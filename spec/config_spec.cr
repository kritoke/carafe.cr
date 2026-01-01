require "spec"
require "../src/config.cr"

describe Carafe::Config do
  # File.open("spec/fixtures/_config.default.yml", "w") do |io|
  #   Carafe::Config.new.to_yaml(io)
  # end

  it ".from_yaml" do
    File.open("spec/fixtures/_config.default.yml", "r") do |io|
      Carafe::Config.from_yaml(io)
    end.should eq Carafe::Config.new
  end

  it ".load_file" do
    Carafe::Config.load_file("spec/fixtures/_config.default.yml").should eq Carafe::Config.new
  end

  it ".load" do
    Carafe::Config.load("spec/fixtures/simple-site/").should eq Carafe::Config.new(site_dir: "spec/fixtures/simple-site/")
  end

  it "loads complex file" do
    config = Carafe::Config.load_file("spec/fixtures/_config.complex.yml")
    config.defaults[0].scope.path.should eq "posts/"
    config.defaults[0].values["layout"].should eq "post"
  end
end
