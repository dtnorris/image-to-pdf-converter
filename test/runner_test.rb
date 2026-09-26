# frozen_string_literal: true

require "open3"
require "rbconfig"

require_relative "test_helper"

class RunnerTest < Minitest::Test
  include TestHelpers

  def test_runner_can_use_input_directory_as_build_directory_without_deleting_sources
    root, input = copy_fixture_dir("synthetic")
    sources = BookPhotoToPdf::ImageFinder.new(input).images
    before = sources.to_h { |path| [File.basename(path), sha256(path)] }

    result = BookPhotoToPdf::Runner.new(
      input_dir: input,
      build_dir: input,
      make_pdf: false
    ).run

    after = sources.to_h { |path| [File.basename(path), sha256(path)] }
    assert_equal before, after
    assert_equal 3, result.input_count
    assert File.file?(File.join(input, "processing-report.csv"))
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_cli_prints_adventure_finder_catalog_next_step_after_pdf_build
    root, input = copy_fixture_dir("synthetic")
    executable = File.expand_path("../bin/book-photo-to-pdf", __dir__)
    expected_catalog = File.expand_path("../../adventure-finder/bin/af-catalog", File.dirname(executable))

    stdout, stderr, status = Open3.capture3(RbConfig.ruby, executable, input)

    assert status.success?, stderr
    pdf_path = File.join(input, "build", "synthetic.pdf")
    assert_includes stdout, "PDF: #{pdf_path}"
    assert_includes stdout, "Next: #{expected_catalog} #{pdf_path}"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_end_to_end_build_creates_pdf
    root, input = copy_fixture_dir("synthetic")

    result = BookPhotoToPdf::Runner.new(input_dir: input).run

    assert File.file?(result.pdf_path)
    assert_operator File.size(result.pdf_path), :>, 0
  ensure
    FileUtils.rm_rf(root) if root
  end
end
