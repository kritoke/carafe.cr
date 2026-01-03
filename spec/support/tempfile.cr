require "file_utils"

{% if flag?(:win32) %}
  SPEC_TEMPFILE_PATH = File.join(Dir.tempdir, "carafe-spec-#{Random.new.hex(4)}").gsub("C:\\", '/').gsub('\\', '/')
{% else %}
  SPEC_TEMPFILE_PATH = File.join(Dir.tempdir, "carafe-spec-#{Random.new.hex(4)}")
{% end %}

SPEC_TEMPFILE_CLEANUP = ENV["SPEC_TEMPFILE_CLEANUP"]? != "0"

def with_tempdir(name, file = __FILE__, &)
  calling_spec = File.basename(file).rchop("_spec.cr")
  path = File.join(SPEC_TEMPFILE_PATH, calling_spec, name)
  FileUtils.mkdir_p(path)

  begin
    yield path
  ensure
    if SPEC_TEMPFILE_CLEANUP
      FileUtils.rm_r(path) if File.exists?(path)
    end
  end
end

if SPEC_TEMPFILE_CLEANUP
  at_exit do
    FileUtils.rm_r(SPEC_TEMPFILE_PATH) if Dir.exists?(SPEC_TEMPFILE_PATH)
  end
end
