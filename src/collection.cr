require "./config"
require "./resource"

class Carafe::Collection
  getter name : String
  getter defaults : Config::Collection
  getter resources : Array(Resource) = [] of Resource

  def initialize(@name : String, @defaults : Config::Collection = Config::Collection.new)
  end

  # Allow Collection to be used in Crinja templates
  def crinja_attribute(name : Crinja::Value)
    case name.to_s
    when "name"
      Crinja::Value.new(@name)
    when "resources"
      # Return Undefined to prevent infinite recursion when wrapping
      Crinja::Value.new(Crinja::Undefined.new("resources"))
    when "output"
      Crinja::Value.new(@defaults.output)
    else
      Crinja::Value.new(Crinja::Undefined.new(name.to_s))
    end
  end
end
