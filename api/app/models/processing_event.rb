class ProcessingEvent < ApplicationRecord
  belongs_to :document

  validates :stage,    presence: true
  validates :to_state, presence: true
  validates :actor,    presence: true
end
