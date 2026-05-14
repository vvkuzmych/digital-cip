class Document < ApplicationRecord
  include AASM

  has_many :chunks, class_name: 'DocumentChunk', dependent: :destroy
  has_many :processing_events, dependent: :destroy

  validates :object_key,   presence: true, uniqueness: true
  validates :content_type, presence: true
  validates :byte_size,    numericality: { greater_than: 0 }
  validates :checksum,     presence: true
  validates :tenant_id,    presence: true

  scope :recent,        -> { order(created_at: :desc) }
  scope :by_tenant,     ->(tenant) { where(tenant_id: tenant) }
  scope :in_state,      ->(state) { where(status: state) }
  scope :pending_work,  -> { where.not(status: %w[embedded failed]) }

  aasm column: :status, whiny_persistence: true do
    state :uploaded, initial: true
    state :ocr_processing
    state :ocr_completed
    state :chunking
    state :chunked
    state :embedding
    state :embedded
    state :failed

    event :start_ocr do
      transitions from: %i[uploaded ocr_completed], to: :ocr_processing
    end

    event :complete_ocr do
      transitions from: :ocr_processing, to: :ocr_completed,
                  after: -> { update!(ocr_completed_at: Time.current) }
    end

    event :start_chunking do
      transitions from: %i[ocr_completed chunked], to: :chunking
    end

    event :complete_chunking do
      transitions from: :chunking, to: :chunked,
                  after: -> { update!(chunked_at: Time.current) }
    end

    event :start_embedding do
      transitions from: %i[chunked embedded], to: :embedding
    end

    event :complete_embedding do
      transitions from: :embedding, to: :embedded,
                  after: -> { update!(embedded_at: Time.current) }
    end

    event :mark_failed do
      transitions to: :failed,
                  after: ->(reason = nil) { update!(failed_at: Time.current, failure_reason: reason) }
    end
  end

  def next_stage
    case status
    when 'uploaded'      then 'ocr'
    when 'ocr_completed' then 'chunk'
    when 'chunked'       then 'embed'
    end
  end

  def record_event!(stage:, to_state:, from_state: nil, message: nil, payload: {})
    processing_events.create!(
      stage: stage,
      from_state: from_state,
      to_state: to_state,
      message: message,
      payload: payload
    )
  end
end
