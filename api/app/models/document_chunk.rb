class DocumentChunk < ApplicationRecord
  belongs_to :document

  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :content,  presence: true
  validates :position, uniqueness: { scope: :document_id }

  scope :ordered, -> { order(:position) }

  def embedding_present?
    self[:embedding].present?
  end
end
