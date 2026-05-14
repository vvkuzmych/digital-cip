class CreateProcessingEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :processing_events do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :stage,        null: false
      t.string  :from_state
      t.string  :to_state,     null: false
      t.string  :actor,        null: false, default: 'system'
      t.text    :message
      t.jsonb   :payload,      null: false, default: {}
      t.datetime :created_at,  null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :processing_events, :stage
    add_index :processing_events, %i[document_id created_at]
  end
end
