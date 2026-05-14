class CreateProcessedMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_messages, id: false do |t|
      t.string  :message_id,      null: false, primary_key: true
      t.string  :idempotency_key, null: false
      t.string  :stage,           null: false
      t.bigint  :document_id
      t.string  :consumer,        null: false
      t.jsonb   :result,          null: false, default: {}
      t.datetime :processed_at,   null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :processed_messages, :idempotency_key
    add_index :processed_messages, :stage
    add_index :processed_messages, :processed_at
  end
end
