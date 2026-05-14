class ProcessedMessage < ApplicationRecord
  self.primary_key = :message_id

  validates :message_id,      presence: true, uniqueness: true
  validates :idempotency_key, presence: true
  validates :stage,           presence: true
  validates :consumer,        presence: true
end
