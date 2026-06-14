require "./jekyll_compat/preprocessor"
require "./jekyll_compat/include_handler"
require "./jekyll_compat/liquid_filters"
require "./jekyll_compat/file_converter"
require "./jekyll_compat/blocks"

module Carafe::JekyllCompat
  def self.register_filters!
    LiquidFilters.register_all!
  end
end
