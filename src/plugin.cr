require "./config"
require "./site"

module Carafe
  abstract class Plugin
    abstract def name : String
    abstract def version : String
    abstract def enabled?(config : Config) : Bool

    def register(site : Site) : Nil
    end

    def self.all_implementations : Array(Plugin.class)
      @@implementations ||= [] of Plugin.class
    end

    def self.inherited(child : Plugin.class)
      all_implementations << child
    end
  end

  class PluginManager
    property plugins : Array(Plugin) = [] of Plugin

    def initialize(@site : Site)
    end

    def load_from_config : Nil
      Plugin.all_implementations.each do |plugin_class|
        plugin = plugin_class.new
        if plugin.enabled?(@site.config)
          @plugins << plugin
          plugin.register(@site)
        end
      end
    end

    def enabled_plugins : Array(Plugin)
      @plugins
    end
  end
end
