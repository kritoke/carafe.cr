require "./config"
require "./site"

module Carafe
  abstract class Plugin
    abstract def name : String
    abstract def version : String
    abstract def enabled?(config : Config) : Bool

    def register(site : Site) : Nil
    end

    @@implementations = [] of Plugin.class

    def self.all_implementations : Array(Plugin.class)
      @@implementations
    end

    def self.register_implementation(impl : Plugin.class)
      @@implementations << impl
    end
  end

  class PluginManager
    property plugins : Array(Plugin) = [] of Plugin

    def initialize(@site : Site)
    end

    def load_from_config : Nil
      puts "Loading plugins... found #{Plugin.all_implementations.size} plugin classes" unless @site.config.quiet?
      Plugin.all_implementations.each do |plugin_class|
        plugin = plugin_class.new
        puts "  Checking plugin: #{plugin.name} (enabled: #{plugin.enabled?(@site.config)})" unless @site.config.quiet?
        if plugin.enabled?(@site.config)
          @plugins << plugin
          plugin.register(@site)
          puts "  Registered plugin: #{plugin.name}" unless @site.config.quiet?
        end
      end
    end

    def enabled_plugins : Array(Plugin)
      @plugins
    end
  end
end
