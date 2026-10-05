# frozen_string_literal: true

require "open3"
require "rbconfig"
require "shellwords"

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
    expected_catalog = "/Users/davidnorris/code/adventure-finder/bin/af-catalog"

    stdout, stderr, status = Open3.capture3({"AF_ADVENTURE_FINDER_ROOT" => nil}, RbConfig.ruby, executable, input)

    assert status.success?, stderr
    pdf_path = File.join(input, "build", "synthetic.pdf")
    assert_includes stdout, "PDF: #{pdf_path}"
    assert_includes stdout, "Next: #{expected_catalog} #{pdf_path}"
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_cli_quotes_explicit_detached_production_front_door
    root, input = copy_fixture_dir("synthetic")
    executable = File.expand_path("../bin/book-photo-to-pdf", __dir__)
    front = File.join(root, "front door", "adventure-finder-production")
    stdout, stderr, status = Open3.capture3(
      {"AF_ADVENTURE_FINDER_ROOT" => front}, RbConfig.ruby, executable, input
    )
    assert status.success?, stderr
    next_line = stdout.lines.find { |line| line.start_with?("Next: ") }
    assert_equal [File.join(front, "bin", "af-catalog"), File.join(input, "build", "synthetic.pdf")],
                 Shellwords.split(next_line.delete_prefix("Next: "))
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
