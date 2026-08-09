# frozen_string_literal: true

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

  def test_end_to_end_build_creates_pdf
    root, input = copy_fixture_dir("synthetic")

    result = BookPhotoToPdf::Runner.new(input_dir: input).run

    assert File.file?(result.pdf_path)
    assert_operator File.size(result.pdf_path), :>, 0
  ensure
    FileUtils.rm_rf(root) if root
  end
end
