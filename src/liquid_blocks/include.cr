require "liquid"

module Liquid::Block
  # Jekyll-compatible Include that supports key=value parameters
  # Extends liquid.cr's Include to add Jekyll-style parameter syntax
  class JekyllInclude < Include
    # Jekyll-style include pattern: file.html key=value key2=value2
    # Note: The parser has already stripped the "include" keyword
    JEKYLL_INCLUDE = /^(?<template_name>[\w\-\.\/]+)(?<params>.*)$/

    def initialize(content : String)
      content = content.strip

      # Debug output to help troubleshoot
      puts "DEBUG: JekyllInclude content = '#{content}'" if ENV["DEBUG_INCLUDE"]?

      # Try Jekyll-style parsing first (no quotes, key=value syntax)
      if match = content.match JEKYLL_INCLUDE
        @template_vars = {} of String => Expression
        @template_name = match["template_name"]

        # Parse key=value parameters
        params_str = match["params"]
        if params_str && !params_str.strip.empty?
          # Parse Jekyll-style key=value parameters
          # This pattern handles: varname=value (where value can be a variable, string, number)
          # We scan repeatedly to get all params
          jekyll_params = /\s*(?<varname>[A-Za-z_]\w*)=(?<value>[^\s]+)/

          params_str.scan(jekyll_params) do |param_match|
            varname = param_match["varname"]
            value = param_match["value"]
            @template_vars[varname] = Expression.new(value)
          end
        end
      else
        # Try liquid.cr syntax (with quotes and colons)
        # Manually parse instead of calling super to avoid issues
        @template_vars = {} of String => Expression

        # Use a pattern for quoted template names (liquid.cr syntax)
        # Note: The parser has already stripped the "include" keyword
        if match = content.match(/^(?<template_name>["'][^"']+["'])(\s+with\s+(?<value>(?:(?:"(?:[^"]|\\")*")|(?:'(?:[^']|\\')*')|(?:[-+]?[0-9]+)|(?:[-!]*(?:[A-Za-z_]\w*)(?:(?:\.[A-Za-z_]\w*)|(?:\[(?:(?:(?:"(?:[^"]|\\")*")|(?:'(?:[^']|\\')*'))|(?:[-+]?[0-9]+)|(?1))\]))*\??))))?/)
          @template_name = match["template_name"].delete("\"").delete("'")
          @template_name += ".liquid" if File.extname(@template_name).empty?

          if match["value"]?
            varname = File.basename(@template_name, File.extname(@template_name))
            @template_vars[varname] = Expression.new(match["value"])
          end
        else
          # Neither pattern matched, raise error
          raise SyntaxError.new("Invalid include Node: #{content}")
        end
      end
    end
  end
end

module Liquid
  class RenderVisitor < Visitor
    # Override visit to create an 'include' hash for Jekyll compatibility
    def visit(node : Liquid::Block::JekyllInclude)
      base_path = @template_path || "."

      # Use liquid.cr's file finding logic with .html → .liquid fallback (Jekyll compatibility)
      filename = if File.exists?(File.join(base_path, node.template_name))
                    File.join(base_path, node.template_name)
                  elsif File.extname(node.template_name) == ".html"
                    # If .html is specified but doesn't exist, try .liquid
                    liquid_path = File.join(base_path, node.template_name.sub(/\.html$/, ".liquid"))
                    if File.exists?(liquid_path)
                      liquid_path
                    else
                      File.join(base_path, node.template_name)
                    end
                  elsif File.extname(node.template_name).empty?
                    # No extension provided, try .liquid first, then .html
                    liquid_path = File.join(base_path, node.template_name + ".liquid")
                    html_path = File.join(base_path, node.template_name + ".html")
                    if File.exists?(liquid_path)
                      liquid_path
                    elsif File.exists?(html_path)
                      html_path
                    else
                      File.join(base_path, node.template_name)
                    end
                  else
                    File.join(base_path, node.template_name)
                  end

      # Create an 'include' hash for include variables (Jekyll compatibility)
      include_hash = {} of String => Liquid::Any

      if node.template_vars != nil
        node.template_vars.each do |key, value|
          evaluated = value.eval(@data)
          # Set both as direct variable and in include hash
          @data.set key, evaluated
          include_hash[key] = evaluated.is_a?(Liquid::Any) ? evaluated : Liquid::Any.new(evaluated)
        end
      end

      # Set the 'include' object in the context
      @data.set "include", Liquid::Any.new(include_hash)

      template_content = File.read filename
      template = Template.parse template_content
      template.template_path = base_path
      @io << template.render(@data)
    end
  end
end

# Register the Jekyll-compatible include to override the default include
Liquid::BlockRegister.register "include", Liquid::Block::JekyllInclude, false

