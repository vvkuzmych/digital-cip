class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.string  :tenant_id, null: false, default: 'default'
      t.string  :title
      t.string  :content_type
      t.bigint  :byte_size
      t.string  :checksum
      t.string  :object_key, null: false
      t.string  :status,     null: false, default: 'uploaded'
      t.text    :raw_text
      t.jsonb   :metadata,   null: false, default: {}
      t.text    :failure_reason
      t.integer :retry_count, null: false, default: 0
      t.datetime :ocr_completed_at
      t.datetime :chunked_at
      t.datetime :embedded_at
      t.datetime :failed_at
      t.timestamps
    end

    add_index :documents, :tenant_id
    add_index :documents, :status
    add_index :documents, :checksum
    add_index :documents, :created_at
  end
end
