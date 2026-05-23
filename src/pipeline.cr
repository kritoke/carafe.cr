require "./processor"

struct Carafe::Pipeline
  getter processors : Array(Processor)

  def initialize(@processors : Array(Processor))
  end

  def pipe(resource : Resource)
    unless resource.has_frontmatter?
      return resource.content
    end

    input = IO::Memory.new
    if content = resource.content
      input << content
      input.rewind
    end

    output = IO::Memory.new

    @processors.each do |processor|
      result = processor.process(resource, input, output)

      # `as(Bool)` ensures all implementations return Bool
      next unless result.as(Bool)

      input.clear
      output.rewind
      input, output = output, input
    end

    input.gets_to_end
  end

  def pipe(io : IO, resource : Resource)
    io << pipe(resource)
  end

  class Builder
    # Processors are auto-discovered through the Processor macro system
    # For configurable processors in the future, could read from site config
    def self.new(site)
      new(site, Processor.all_implementations)
    end

    def self.new(site, types : Array(Processor.class))
      transforms = [] of Processor::Transformation

      types.each do |klass|
        processor = klass.new(site)
        transforms += processor.transformations
      end

      new site, transforms
    end

    def initialize(@site : Site, @transforms : Array(Processor::Transformation))
      @transforms.sort!
      @register = Hash(String, Pipeline).new do |hash, key|
        hash[key] = create_pipeline(key)
      end
    end

    def transformation_for_extension(extension) : Processor::Transformation?
      extension = extension.lchop('.')

      @transforms.each do |transform|
        next if transform.from_wildcard? || transform.to_wildcard? || transform.from_first == transform.to_first

        processor = transform.processor
        if processor.responds_to? :file_extensions
          input_extensions = processor.file_extensions(transform.from)
        else
          input_extensions = {transform.from}
        end

        input_extensions.each do |input_ext|
          if extension == input_ext
            return transform
          end
        end
      end
    end

    def format_for_filename(filename : String) : String
      input_ext = File.extname(filename)
      transformation = transformation_for_extension(input_ext)

      # Only use transformation result if one exists, otherwise use raw extension
      transformation ? transformation.from : input_ext
    end

    def format_for(resource : Resource) : String
      ext = format_for_filename(resource.slug)
      # Don't add extra dot if ext already starts with dot
      if ext.starts_with?('.')
        "liquid#{ext}"
      else
        "liquid.#{ext}"
      end
    end

    def pipeline_for(resource : Resource) : Pipeline
      @register[format_for(resource)]
    end

    def output_ext(input_ext : String) : String?
      if transformation = transformation_for_extension(input_ext)
        ".#{transformation.to}"
      end
    end

    def output_ext_for(resource : Resource) : String?
      extname = resource.extname

      if extname && resource.has_frontmatter?
        output_ext(extname) || extname
      else
        extname
      end
    end

    def create_pipeline(format)
      segments = [] of Processor

      # Clean the prefix immediately
      if format.starts_with?("liquid.")
        format = format[7..-1]
      end

      # 1. First Pass: Always capture global pre-filters/pre-processors (like Liquid)
      # that are designed to handle this incoming format before structural mutation
      @transforms.each do |t|
        if t.from_wildcard? && t.to == "liquid"
          segments << t.processor
        end
      end

      # 2. Second Pass: Find specific file-type converters matching the exact format
      # (e.g., "markdown -> html" or "scss -> css")
      specific_transform = @transforms.find do |t|
        !t.from_wildcard? && (t.from == format || format.starts_with?(t.from))
      end
      
      if specific_transform
        segments << specific_transform.processor
        # Update the target format based on what it converted to
        format = specific_transform.to
      end

      # 3. Third Pass: Append terminal layout/output processing blocks
      layout_transform = @transforms.find do |t|
        t.from_wildcard? && t.to == "output"
      end

      if layout_transform && !segments.includes?(layout_transform.processor)
        segments << layout_transform.processor
      end

      Pipeline.new(segments.uniq)
    end
  end
end
