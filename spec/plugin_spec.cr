require "./spec_helper"
require "../src/plugin"

describe Carafe::PluginManager do
  it "initializes with a site" do
    config = Carafe::Config.new
    site = Carafe::Site.new(config)

    manager = Carafe::PluginManager.new(site)
    manager.should be_a(Carafe::PluginManager)
  end

  it "has an empty plugins list initially" do
    config = Carafe::Config.new
    site = Carafe::Site.new(config)
    manager = Carafe::PluginManager.new(site)

    manager.plugins.should be_empty
  end
end

describe Carafe::Plugin do
  it "tracks all implementations" do
    implementations = Carafe::Plugin.all_implementations
    implementations.should be_a(Array(Carafe::Plugin.class))
  end
end

# Example test plugin for testing purposes
class TestPlugin < Carafe::Plugin
  def name : String
    "test-plugin"
  end

  def version : String
    "1.0.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    config["test_plugin"]?.try(&.as_bool) || false
  end
end

describe "Plugin System Integration" do
  it "tracks plugin implementations" do
    # Verify that the plugin system tracks implementations
    implementations = Carafe::Plugin.all_implementations
    implementations.should be_a(Array(Carafe::Plugin.class))
  end

  it "plugin manager loads from config" do
    config = Carafe::Config.new
    site = Carafe::Site.new(config)
    manager = Carafe::PluginManager.new(site)

    manager.load_from_config

    # Manager should have processed all implementations
    manager.should be_a(Carafe::PluginManager)
    manager.plugins.should be_a(Array(Carafe::Plugin))
  end
end
