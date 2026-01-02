require "spec"
require "../src/config.cr"

describe Carafe::Config do
  # File.open("spec/fixtures/_config.default.yml", "w") do |io|
  #   Carafe::Config.new.to_yaml(io)
  # end

  it ".from_yaml" do
    File.open("spec/fixtures/_config.default.yml", "r") do |io|
      config = Carafe::Config.from_yaml(io)
      config.collections["posts"]["permalink"].should eq "/posts/:year-:month-:day-:title/"
    end
  end

  it ".load_file" do
    config = Carafe::Config.load_file("spec/fixtures/_config.default.yml")
    config.collections["posts"]["permalink"].should eq "/posts/:year-:month-:day-:title/"
  end

  it ".load" do
    config = Carafe::Config.load("spec/fixtures/simple-site/")
    config.site_dir.should eq "spec/fixtures/simple-site/"
    config.port.should eq 4001
  end

  it "loads complex file" do
    config = Carafe::Config.load_file("spec/fixtures/_config.complex.yml")
    config.defaults[0].scope.path.should eq "posts/"
    config.defaults[0].values["layout"].should eq "post"
  end
end
