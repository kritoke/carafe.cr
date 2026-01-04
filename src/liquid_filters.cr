require "liquid"

# Jekyll-compatible Liquid filters for carafe
module Carafe::LiquidFilters
  # Jekyll's where_exp filter - filters array based on expression
  #
  # Usage: {{ array | where_exp: "item", "item.property == value" }}
  class WhereExp
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      raise Liquid::FilterArgumentException.new("where_exp filter expects two arguments.") if args.size != 2

      item_var = args[0].to_s
      expression = args[1].to_s

      raw_data = data.raw

      # Return empty array if data is nil
      return Liquid::Any.new([] of Liquid::Any) if raw_data.nil?

      if raw_data.is_a?(Array)
        # Filter the array based on the expression
        filtered_array = raw_data.select do |item|
          evaluate_expression(item, item_var, expression)
        end

        # Convert to Array(Liquid::Any) if needed
        # If items are Hash, we need to wrap them
        converted_array = filtered_array.map do |item|
          item.is_a?(Liquid::Any) ? item : Liquid::Any.new(item)
        end

        # Return the filtered array wrapped in Liquid::Any
        Liquid::Any.new(converted_array)
      else
        # data is not an array, return it as-is
        data
      end
    end

    # Evaluate a simple expression against an item
    private def self.evaluate_expression(item, item_var : String, expression : String) : Bool
      # Parse simple expressions like:
      # - "item.property != false"
      # - "item.search != false"
      # - "item.title != null"

      # Extract property and comparison
      # Pattern: item.<property> <operator> <value>
      if expression.match(/^#{item_var}\.(\w+)\s*(!=|==|>=|<=|>|<)\s*(.+)$/)
        property = $1
        operator = $2
        value_str = $3

        # Get the property value from the item
        property_value = get_property_value(item, property)

        # Parse the comparison value
        comparison_value = parse_value(value_str)

        # Perform the comparison
        # For now, only handle != and == operators to avoid type issues
        case operator
        when "!="
          property_value != comparison_value
        when "=="
          property_value == comparison_value
        else
          # For other operators, try to compare as strings or return true
          begin
            property_value.to_s != comparison_value.to_s
          rescue
            true
          end
        end
      else
        # If we can't parse the expression, return true (include the item)
        true
      end
    end

    # Get a property value from an item (can be Hash, Liquid::Any, or Object)
    private def self.get_property_value(item, property : String)
      case item
      when Liquid::Any
        get_property_value(item.raw, property)
      when Hash
        if hash_value = item[property]?
          hash_value.is_a?(Liquid::Any) ? hash_value.raw : hash_value
        else
          nil
        end
      else
        nil
      end
    end

    # Parse a value string (handles "false", "true", "null", numbers, strings)
    private def self.parse_value(value_str : String)
      value_str = value_str.strip

      case value_str
      when "false"
        false
      when "true"
        true
      when "null", "nil"
        nil
      when /^\d+$/
        value_str.to_i
      when /^\d+\.\d+$/
        value_str.to_f
      else
        # Remove quotes if present
        if value_str.starts_with?('"') || value_str.starts_with?("'")
          value_str[1..-2]
        else
          value_str
        end
      end
    end
  end

  # Register the filter with Liquid
  Liquid::Filters::FilterRegister.register "where_exp", Carafe::LiquidFilters::WhereExp
end
