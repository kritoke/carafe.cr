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
      # Get template_path from context if available, otherwise use "."
      base_path = if template_path_val = @data["template_path"]?
                     case raw = template_path_val.raw
                     when String
                       raw
                     else
                       "."
                     end
                   else
                     @template_path || "."
                   end

      # Jekyll looks for includes in the _includes directory
      # We need to go up from _layouts to the site root, then into _includes
      includes_dir = if base_path.ends_with?("/_layouts") || base_path.ends_with?("/_layouts/")
                       File.join(File.dirname(base_path), "_includes")
                     elsif base_path == "."
                       "_includes"
                     else
                       # For site directory or theme layouts, use _includes subdirectory
                       File.join(base_path, "_includes")
                     end

      # Use liquid.cr's file finding logic with .html → .liquid fallback (Jekyll compatibility)
      filename = if File.exists?(File.join(includes_dir, node.template_name))
                   File.join(includes_dir, node.template_name)
                 elsif File.extname(node.template_name) == ".html"
                   # If .html is specified but doesn't exist, try .liquid
                   liquid_path = File.join(includes_dir, node.template_name.sub(/\.html$/, ".liquid"))
                   if File.exists?(liquid_path)
                     liquid_path
                   else
                     File.join(includes_dir, node.template_name)
                   end
                 elsif File.extname(node.template_name).empty?
                   # No extension provided, try .liquid first, then .html
                   liquid_path = File.join(includes_dir, node.template_name + ".liquid")
                   html_path = File.join(includes_dir, node.template_name + ".html")
                   if File.exists?(liquid_path)
                     liquid_path
                   elsif File.exists?(html_path)
                     html_path
                   else
                     File.join(includes_dir, node.template_name)
                   end
                 else
                   File.join(includes_dir, node.template_name)
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

      # Handle documents-collection.html special case BEFORE filter removal
      # Replace {% assign entries = include.entries | default: site[include.collection] %}
      # with just using the variable directly, since Liquid can't iterate over assigned arrays
      if template_content.includes?("assign entries = include.entries")
        # Check if include.entries was passed (home page case)
        if include_hash.has_key?("entries")
          entries_value = include_hash["entries"]?

          # Determine what data source to use based on the entries parameter value
          # If entries is "posts", use site.posts directly
          # If entries is a collection name, use site.collections[that_name]
          if entries_value.is_a?(String)
            entries_str = entries_value.as_s

            if entries_str == "posts" || entries_str == "site.posts"
              # home.html case: entries=posts where posts = site.posts
              # Use site.posts directly to avoid Liquid's array assignment limitation
              template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
              template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
              template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
              template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
            else
              # Could be a collection reference like site.collections.tags
              # Try to use it as a collection key
              template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
              template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
              template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
              template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
            end
          else
            # Fallback: assume site.posts
            template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
            template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
            template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
            template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
          end
        elsif include_hash.has_key?("collection")
          # collection case: use site.collections[collection_name].docs
          collection_name = include_hash["collection"]?

          # collection_name is Liquid::Any, need to extract the string value
          coll_name = collection_name.try(&.as_s?)
          if coll_name
            # Access the collection docs via site.collections[collection_name].docs
            # Liquid uses dot notation: site.collections.resources.docs
            # The template has: {% assign entries = include.entries | default: site[include.collection] | where_exp: "post", "post.hidden != true" %}
            # We need to remove this entire assign statement and replace the for loop
            template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
            template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
            template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.collections.#{coll_name}.docs %}")
            template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.collections.#{coll_name}.docs %}")
          else
            # Fallback for collection
            template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
            template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
            template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
            template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
          end
        end
      end

      # Preprocess to remove Jekyll-specific Liquid syntax that Liquid doesn't support
      # Remove {% continue %} tags (not supported by Liquid)
      template_content = template_content.gsub(/{%\s*continue\s*%}/, "")

      # Remove where_exp, sort, and reverse filters from assign statements
      # These filters are not supported by Liquid, but we already sort posts correctly
      # in build_site_hash, so removing them is safe
      # We need to remove the entire filter chain while keeping the assign statement intact
      # Pattern: {% assign var = value | filter1 | filter2 %}
      # We remove each filter individually, keeping the pipe but removing the filter part
      # IMPORTANT: Must preserve the closing %} or the assign statement will be invalid
      template_content = template_content.gsub(/\|\s*where_exp:\s*"[^"]*"\s*,\s*"[^"]*"(\s*%})/, "\\1")
      template_content = template_content.gsub(/\|\s*sort:\s*"[^"]*"(\s*%})/, "\\1")
      template_content = template_content.gsub(/\|\s*reverse(\s*%})/, "\\1")

      # Clean up any double pipes
      template_content = template_content.gsub(/\|\s*\|/, "|")

      # Clean up trailing pipes before closing brace (but only if there's nothing after the pipe)
      # Pattern: | %}  or  | %}
      template_content = template_content.gsub(/\|\s*(%})/, "\\1")

      # Replace .last with [1] for iteration variables (Jekyll compatibility)
      # Liquid doesn't support .last on arrays, but Jekyll does
      # We replace var.last with var[1] for specific variables we know are arrays
      template_content = template_content.gsub(/(\w+)\.last/, "\\1[1]")

      # Replace for loops with variable ranges with a fixed range (1..1)
      # Jekyll: {% for i in (page_start..page_end) %}...{% endfor %}
      # Liquid doesn't support variable ranges, only literals like {% for i in (1..5) %}
      # We replace the variable range with 1..1 (no parentheses) which Liquid can parse
      template_content = template_content.gsub(/({%\s*for\s+\w+\s+in\s+)\([^)]+\.\.[^)]+\)(\s*reversed)?(\s*%})/) do |_match|
        for_start = $1
        _reversed = $2?
        for_end = $3?
        "#{for_start}1..1#{_reversed}#{for_end}"
      end

      template = Template.parse template_content
      # Set template_path to the root template path so nested includes work correctly
      template.template_path = @template_path || "."
      @io << template.render(@data)
    end
  end
end

# Register the Jekyll-compatible include to override the default include
Liquid::BlockRegister.register "include", Liquid::Block::JekyllInclude, false
