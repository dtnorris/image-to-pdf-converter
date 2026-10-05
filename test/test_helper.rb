# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require "minitest/autorun"

# Use the environment installed by bin/setup without requiring shell activation.
# Keep an explicit interpreter override authoritative, including in CLI subprocesses.
ENV["BOOK_PHOTO_PYTHON"] ||= begin
  local_python = File.expand_path("../.venv/bin/python", __dir__)
  File.file?(local_python) && File.executable?(local_python) ? local_python : "python3"
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "book_photo_to_pdf"

module TestHelpers
  def fixture_path(*parts)
    File.expand_path(File.join("fixtures", *parts), __dir__)
  end

  def copy_fixture_dir(name)
    root = Dir.mktmpdir("book-photo-to-pdf-test")
    input = File.join(root, name)
    FileUtils.cp_r(fixture_path(name), input)
    [root, input]
  end

  def sha256(path)
    Digest::SHA256.file(path).hexdigest
  end
end
