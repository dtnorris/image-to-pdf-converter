# frozen_string_literal: true

module BookPhotoToPdf
  class ImageFinder
    IMAGE_EXTENSIONS = %w[.jpg .jpeg].freeze

    attr_reader :input_dir

    def initialize(input_dir)
      @input_dir = File.expand_path(input_dir)
    end

    def images
      @images ||= begin
        raise Error, "Input directory does not exist: #{input_dir}" unless Dir.exist?(input_dir)

        found = Dir.children(input_dir).filter_map do |name|
          path = File.join(input_dir, name)
          next unless File.file?(path)
          next unless IMAGE_EXTENSIONS.include?(File.extname(name).downcase)

          path
        end

        found.sort_by { |path| natural_sort_key(File.basename(path)) }
      end
    end

    def sequence_gaps
      numbered = images.filter_map do |path|
        match = File.basename(path, File.extname(path)).match(/(\d+)\z/)
        match && match[1].to_i
      end
      return [] if numbered.length < 2

      ((numbered.min)..(numbered.max)).to_a - numbered.uniq
    end

    private

    def natural_sort_key(name)
      name.downcase.split(/(\d+)/).map do |part|
        part.match?(/\A\d+\z/) ? [0, part.to_i] : [1, part]
      end
    end
  end
end
