# frozen_string_literal: true

require "fileutils"

module BookPhotoToPdf
  class Runner
    Result = Struct.new(:input_count, :sequence_gaps, :build_dir, :pdf_path, :report_path, keyword_init: true)

    attr_reader :input_dir, :build_dir, :pdf_path, :python, :diagnostics, :make_pdf

    def initialize(input_dir:, build_dir: nil, pdf_path: nil, python: ENV.fetch("BOOK_PHOTO_PYTHON", "python3"), diagnostics: false, make_pdf: true)
      @input_dir = File.expand_path(input_dir)
      @build_dir = File.expand_path(build_dir || File.join(@input_dir, "build"))
      basename = File.basename(@input_dir.sub(%r{/+\z}, ""))
      @pdf_path = File.expand_path(pdf_path || File.join(@build_dir, "#{basename}.pdf"))
      @python = python
      @diagnostics = diagnostics
      @make_pdf = make_pdf
    end

    def run
      finder = ImageFinder.new(input_dir)
      images = finder.images
      raise Error, "No JPG/JPEG images found directly in #{input_dir}" if images.empty?
      if make_pdf && File.extname(pdf_path).downcase != ".pdf"
        raise Error, "Output file must end in .pdf: #{pdf_path}"
      end

      prepare_build_dir
      processor = Processor.new(images: images, build_dir: build_dir, python: python, diagnostics: diagnostics)
      processed = processor.run
      PdfBuilder.new(images: processed, output_path: pdf_path, python: python).build if make_pdf

      Result.new(
        input_count: images.length,
        sequence_gaps: finder.sequence_gaps,
        build_dir: build_dir,
        pdf_path: make_pdf ? pdf_path : nil,
        report_path: processor.report_path
      )
    end

    private

    def prepare_build_dir
      # Never recursively delete directories here. Generated files are overwritten
      # by name, which keeps a mistaken --build-dir from erasing unrelated data.
      FileUtils.mkdir_p(build_dir)
      %w[input-manifest.txt processing-report.csv].each do |name|
        FileUtils.rm_f(File.join(build_dir, name))
      end
      FileUtils.rm_f(pdf_path) if File.dirname(pdf_path) == build_dir
    end
  end
end
