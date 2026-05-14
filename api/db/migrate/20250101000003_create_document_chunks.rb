class CreateDocumentChunks < ActiveRecord::Migration[8.0]
  def change
    embedding_dim = ENV.fetch('EMBEDDING_DIM', 384).to_i

    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text    :content,  null: false
      t.integer :token_count
      t.jsonb   :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :document_chunks, %i[document_id position], unique: true

    execute <<~SQL
      ALTER TABLE document_chunks
        ADD COLUMN embedding vector(#{embedding_dim});
    SQL

    execute <<~SQL
      CREATE INDEX document_chunks_embedding_idx
        ON document_chunks
        USING hnsw (embedding vector_cosine_ops);
    SQL
  end
end
