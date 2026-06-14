module Carafe::JekyllCompat
  module FileConverter
    extend self

    def convert_html_to_liquid(content : String) : String
      content.gsub(/\{%\s*include\s+([^\s]+?)\.html(\s+.*?)?\s*%\}/) do
        name = $1
        params = $2? || ""

        converted = if params.strip.empty?
                      ""
                    else
                      ", " + convert_params(params).join(", ")
                    end

        "{% include #{name}.liquid#{converted} %}"
      end
    end

    private def convert_params(params : String) : Array(String)
      params.scan(/(\w+)=([^\s%]+)/).map do |m|
        key = m[1]
        val = m[2]
        if val =~ /^[a-zA-Z_][a-zA-Z0-9_.\[\]]*$/
          "#{key}: #{val}"
        else
          "#{key}: \"#{val}\""
        end
      end
    end

    def copy_html_includes(dir : String) : Array(String)
      return [] of String unless Dir.exists?(dir)

      copied = [] of String
      Dir.glob(File.join(dir, "*.html")).each do |html|
        liquid = html.sub(/\.html$/, ".liquid")
        next if File.exists?(liquid)

        File.write(liquid, convert_html_to_liquid(File.read(html)))
        copied << liquid
      end
      copied
    end
  end
end
