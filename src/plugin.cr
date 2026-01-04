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
      puts "DEBUG: Loading plugins from config..." unless @site.config.quiet?
      puts "DEBUG: Found #{Plugin.all_implementations.size} registered plugin classes" unless @site.config.quiet?
      Plugin.all_implementations.each do |plugin_class|
        puts "DEBUG: Checking plugin: #{plugin_class.new.name}" unless @site.config.quiet?
        plugin = plugin_class.new
        if plugin.enabled?(@site.config)
          puts "DEBUG: Enabling plugin: #{plugin.name}" unless @site.config.quiet?
          @plugins << plugin
          plugin.register(@site)
        else
          puts "DEBUG: Plugin #{plugin.name} not enabled" unless @site.config.quiet?
        end
      end
      puts "DEBUG: Loaded #{@plugins.size} plugins" unless @site.config.quiet?
    end

    def enabled_plugins : Array(Plugin)
      @plugins
    end
  end
end
