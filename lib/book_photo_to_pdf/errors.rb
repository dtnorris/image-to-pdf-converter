# frozen_string_literal: true

module BookPhotoToPdf
  class Error < StandardError; end
  class DependencyError < Error; end
  class ProcessingError < Error; end
end
