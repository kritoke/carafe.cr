require "./config"
require "./resource"

class Carafe::Collection
  getter name : String
  getter defaults : Config::Collection
  getter resources : Array(Resource) = [] of Resource
  getter? output : Bool

  def initialize(@name : String, @defaults : Config::Collection = Config::Collection.new)
    @output = @defaults.output?
  end
end
