# frozen_string_literal: true

require "open3"
require "fileutils"

module BookPhotoToPdf
  class PdfBuilder
    attr_reader :images, :output_path, :python

    def initialize(images:, output_path:, python: ENV.fetch("BOOK_PHOTO_PYTHON", "python3"))
      @images = images
      @output_path = File.expand_path(output_path)
      @python = python
    end

    def build
      raise Error, "No processed images available for PDF assembly" if images.empty?

      FileUtils.mkdir_p(File.dirname(output_path))
      if executable?("img2pdf")
        run!(["img2pdf", *images, "-o", output_path], "img2pdf")
      else
        fallback = File.expand_path("../../scripts/make_pdf.py", __dir__)
        run!([python, fallback, "--output", output_path, *images], "PDF fallback")
      end
      output_path
    rescue Errno::ENOENT => e
      raise DependencyError, "PDF assembly dependency is unavailable: #{e.message}"
    end

    private

    def executable?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        path = File.join(dir, name)
        File.file?(path) && File.executable?(path)
      end
    end

    def run!(command, label)
      stdout, stderr, status = Open3.capture3(*command)
      return if status.success?

      detail = stderr.to_s.strip
      detail = stdout.to_s.strip if detail.empty?
      raise ProcessingError, "#{label} failed#{detail.empty? ? "" : ": #{detail}"}"
    end
  end
end
