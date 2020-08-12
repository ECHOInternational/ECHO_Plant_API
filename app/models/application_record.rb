# frozen_string_literal: true

# Sets defaults for all ActiveRecord based models
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  has_paper_trail
end
