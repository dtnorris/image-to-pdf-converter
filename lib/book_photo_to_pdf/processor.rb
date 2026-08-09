# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"

module BookPhotoToPdf
  class Processor
    attr_reader :images, :build_dir, :python, :diagnostics, :stderr, :stdout

    def initialize(images:, build_dir:, python: ENV.fetch("BOOK_PHOTO_PYTHON", "python3"), diagnostics: false)
      @images = images
      @build_dir = File.expand_path(build_dir)
      @python = python
      @diagnostics = diagnostics
    end

    def run
      raise Error, "No JPG/JPEG images found" if images.empty?

      FileUtils.mkdir_p(build_dir)
      manifest = File.join(build_dir, "input-manifest.txt")
      File.write(manifest, images.join("\n") + "\n")

      script = File.expand_path("../../scripts/process_pages.py", __dir__)
      command = [python, script, "--manifest", manifest, "--output-dir", processed_dir, "--report", report_path]
      command << "--diagnostics" if diagnostics

      @stdout, @stderr, status = Open3.capture3(*command)
      unless status.success?
        message = stderr.to_s.strip
        message = stdout.to_s.strip if message.empty?
        raise ProcessingError, "Page preprocessing failed#{message.empty? ? "" : ": #{message}"}"
      end

      processed_images
    rescue Errno::ENOENT
      raise DependencyError,
            "Could not run #{python.inspect}. Install Python 3, create a venv, and run `pip install -r requirements.txt`."
    end

    def processed_dir
      File.join(build_dir, "processed")
    end

    def report_path
      File.join(build_dir, "processing-report.csv")
    end

    def processed_images
      images.map { |path| File.join(processed_dir, File.basename(path)) }
    end
  end
end
