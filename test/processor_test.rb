# frozen_string_literal: true

require "csv"
require_relative "test_helper"

class ProcessorTest < Minitest::Test
  include TestHelpers

  def test_processes_without_modifying_sources_and_normalizes_dimensions
    root, input = copy_fixture_dir("synthetic")
    build = File.join(input, "build")
    images = BookPhotoToPdf::ImageFinder.new(input).images
    before = images.to_h { |path| [File.basename(path), sha256(path)] }

    processor = BookPhotoToPdf::Processor.new(images: images, build_dir: build)
    outputs = processor.run

    assert_equal 3, outputs.length
    outputs.each { |path| assert File.file?(path), "expected #{path} to exist" }
    assert File.file?(processor.report_path)

    after = images.to_h { |path| [File.basename(path), sha256(path)] }
    assert_equal before, after, "source photographs must never be modified"

    dimensions = outputs.map do |path|
      stdout = IO.popen(["python3", "-c", "from PIL import Image; import sys; print('x'.join(map(str, Image.open(sys.argv[1]).size)))", path], &:read).strip
      stdout
    end
    assert_equal 1, dimensions.uniq.length, "all processed pages should share one canvas size"

    rows = CSV.read(processor.report_path, headers: true)
    assert_equal 3, rows.length
    assert rows.all? { |row| %w[high medium low].include?(row["confidence"]) }
  ensure
    FileUtils.rm_rf(root) if root
  end

  def test_low_confidence_does_not_require_a_crop
    root = Dir.mktmpdir("book-photo-low-confidence")
    input = File.join(root, "input")
    FileUtils.mkdir_p(input)
    image = File.join(input, "IMG_0001.jpg")
    system("python3", "-c", "from PIL import Image; Image.new('RGB',(600,800),'white').save(r'#{image}','JPEG')", exception: true)

    processor = BookPhotoToPdf::Processor.new(images: [image], build_dir: File.join(input, "build"))
    processor.run
    row = CSV.read(processor.report_path, headers: true).first

    assert_equal "low", row["confidence"]
    assert_equal "0", row["crop_left"]
    assert_equal "0", row["crop_top"]
    assert_equal "600", row["crop_right"]
    assert_equal "800", row["crop_bottom"]
  ensure
    FileUtils.rm_rf(root) if root
  end
end
