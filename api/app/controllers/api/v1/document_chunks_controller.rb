module Api
  module V1
    class DocumentChunksController < ApplicationController
      def index
        document = Document.find(params[:document_id])
        chunks = document.chunks.ordered.page(params[:page]).per(params[:per_page] || 50)

        render json: {
          document_id: document.id,
          status: document.status,
          chunks: chunks.map do |c|
            {
              id: c.id,
              position: c.position,
              content: c.content,
              token_count: c.token_count,
              has_embedding: c.embedding_present?
            }
          end,
          meta: {
            page: chunks.current_page,
            per_page: chunks.limit_value,
            total_pages: chunks.total_pages,
            total_count: chunks.total_count
          }
        }
      end
    end
  end
end
