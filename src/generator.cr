require "./site"
require "./priority"

abstract class Carafe::Generator
  getter site : Site

  def initialize(@site : Site)
  end

  abstract def generate : Nil

  abstract def priority : Priority
end

require "./generator/*"
