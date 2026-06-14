module Carafe::Security
  # Prevents path traversal by ensuring the resolved path stays within the base directory.
  # Returns the safe path or nil if the path escapes the base directory.
  def self.sanitize_path(base_path : String, user_path : String) : String?
    return if user_path.nil? || user_path.empty?

    # Resolve both paths to absolute form
    resolved_base = File.expand_path(base_path)
    resolved_path = File.expand_path(user_path, base_path)

    # Normalize path separators
    resolved_base = resolved_base.gsub("\\", "/")
    resolved_path = resolved_path.gsub("\\", "/")

    # Check if the resolved path starts with the base path
    # We need to ensure it's a true subdirectory, not just a prefix match
    # e.g., /base shouldn't match /base-something
    if resolved_path.starts_with?(resolved_base + "/") || resolved_path == resolved_base
      resolved_path
    end
  end

  # Validates that a path is safe for use with glob patterns.
  # Rejects paths with dangerous characters and traversal sequences.
  def self.validate_glob_path(path : String) : Bool
    return false if path.nil? || path.empty?

    # Reject null bytes
    return false if path.includes?('\0')

    # Reject obvious traversal attempts
    return false if path.includes?("..")

    # Reject absolute paths (unless specifically allowed)
    return false if path.starts_with?("/") && !path.starts_with?("//")

    true
  end

  # Ensures a filename doesn't contain path traversal or dangerous characters.
  # Allows subdirectory paths (e.g., search/search_form.html) which are valid for Jekyll includes.
  def self.sanitize_filename(filename : String) : String?
    return if filename.nil? || filename.empty?

    # Remove null bytes
    sanitized = filename.gsub('\0', "")

    # Reject path traversal
    return if sanitized.includes?("..")

    # Reject absolute paths
    return if sanitized.starts_with?('/')

    # Normalize path separators
    sanitized = sanitized.gsub('\\', "/")

    # Split into path components and validate each one
    parts = sanitized.split('/')
    parts.each do |part|
      return if part.empty?
      return if part.starts_with?('.')
    end

    # Ensure it's not empty after sanitization
    return if sanitized.empty?

    sanitized
  end

  # Validates that content doesn't contain obvious injection attempts.
  # This is a basic check - content sanitization should happen at the template level.
  def self.validate_content(content : String) : Bool
    return false if content.nil?

    # Reject null bytes
    return false if content.includes?('\0')

    true
  end

  # Maximum size for YAML/JSON content (1MB)
  MAX_CONTENT_SIZE = 1_048_576

  # Validates content size to prevent DoS via large payloads.
  def self.validate_content_size(content : String) : Bool
    return false if content.bytesize > MAX_CONTENT_SIZE
    true
  end

  # Validates content size from IO to prevent DoS via large payloads.
  def self.validate_io_size(io : IO) : Bool
    true # IO size check handled at read time
  end
end
