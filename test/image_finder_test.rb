# frozen_string_literal: true

require_relative "test_helper"

class ImageFinderTest < Minitest::Test
  include TestHelpers

  def test_finds_jpegs_case_insensitively_and_naturally_sorts_numbers
    finder = BookPhotoToPdf::ImageFinder.new(fixture_path("synthetic"))

    assert_equal %w[IMG_0001.JPG IMG_0002.jpg IMG_0010.JPG], finder.images.map { |p| File.basename(p) }
  end

  def test_reports_numeric_sequence_gaps_without_treating_them_as_fatal
    finder = BookPhotoToPdf::ImageFinder.new(fixture_path("synthetic"))

    assert_equal (3..9).to_a, finder.sequence_gaps
  end
end
