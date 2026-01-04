require "../generator"
require "yaml"

class Carafe::Generator::Data < Carafe::Generator
  def priority : Priority
    Priority::LOW
  end

  def generate : Nil
    data_dir = File.join(@site.site_dir, @site.config.data_dir)

    return unless Dir.exists?(data_dir)

    load_data_files(data_dir)
    nil
  end

  private def load_data_files(dir : String)
    Dir.entries(dir).each do |entry|
      next if entry.starts_with?(".")

      full_path = File.join(dir, entry)

      if File.directory?(full_path)
        # It's a directory - create nested hash and recurse
        @site.data[entry] = YAML.parse("{}")
        merge_yaml_from_dir(full_path, @site.data[entry].as_h)
      elsif File.file?(full_path)
        # It's a file - load YAML/JSON and add to hash
        ext = File.extname(entry)
        if ext == ".yml" || ext == ".yaml" || ext == ".json"
          key = File.basename(entry, ext)
          content = File.read(full_path)

          if ext == ".json"
            # Parse JSON - convert to string then parse as YAML
            json_obj = JSON.parse(content)
            @site.data[key] = YAML.parse(json_obj.to_yaml)
          else
            # Parse YAML
            @site.data[key] = YAML.parse(content)
          end
        end
      end
    end
  end

  private def merge_yaml_from_dir(dir : String, target_hash : Hash(YAML::Any, YAML::Any))
    Dir.entries(dir).each do |entry|
      next if entry.starts_with?(".")

      full_path = File.join(dir, entry)

      if File.directory?(full_path)
        # It's a directory - create nested hash
        nested = YAML.parse("{}")
        target_hash[YAML::Any.new(entry)] = nested
        merge_yaml_from_dir(full_path, nested.as_h)
      elsif File.file?(full_path)
        # It's a file - load YAML/JSON and add to hash
        ext = File.extname(entry)
        if ext == ".yml" || ext == ".yaml" || ext == ".json"
          key = File.basename(entry, ext)
          content = File.read(full_path)

          if ext == ".json"
            # Parse JSON - convert to string then parse as YAML
            json_obj = JSON.parse(content)
            target_hash[YAML::Any.new(key)] = YAML.parse(json_obj.to_yaml)
          else
            # Parse YAML
            target_hash[YAML::Any.new(key)] = YAML.parse(content)
          end
        end
      end
    end
  end
end
