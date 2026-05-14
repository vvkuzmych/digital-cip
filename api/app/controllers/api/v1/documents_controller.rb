module Api
  module V1
    class DocumentsController < ApplicationController
      before_action :set_document, only: %i[show retry]

      def index
        documents = Document.recent.page(params[:page]).per(params[:per_page] || 25)
        render json: documents.map { |d| serialize(d) }, meta: pagination_meta(documents)
      end

      def show
        render json: serialize(@document, include_events: true)
      end

      def create
        upload = params[:file] || params.dig(:document, :file)
        return render json: { error: 'file is required' }, status: :unprocessable_entity if upload.blank?

        result = Ingestion::CreateDocument.new(
          upload: upload,
          title: params[:title],
          tenant_id: params[:tenant_id] || 'default'
        ).call

        if result[:success]
          render json: serialize(result[:data][:document]), status: :accepted
        else
          render json: { error: 'invalid', message: result[:message] }, status: :unprocessable_entity
        end
      end

      def retry
        result = Ingestion::RetryDocument.new(@document).call
        status = result[:success] ? :accepted : :unprocessable_entity
        render json: { message: result[:message], document: serialize(@document) }, status: status
      end

      private

      def set_document
        @document = Document.find(params[:id])
      end

      def serialize(document, include_events: false)
        payload = {
          id: document.id,
          tenant_id: document.tenant_id,
          title: document.title,
          status: document.status,
          content_type: document.content_type,
          byte_size: document.byte_size,
          checksum: document.checksum,
          object_key: document.object_key,
          retry_count: document.retry_count,
          failure_reason: document.failure_reason,
          ocr_completed_at: document.ocr_completed_at,
          chunked_at: document.chunked_at,
          embedded_at: document.embedded_at,
          chunks_count: document.chunks.count,
          created_at: document.created_at
        }
        payload[:events] = document.processing_events.order(:created_at).limit(50).map do |e|
          { stage: e.stage, from: e.from_state, to: e.to_state, actor: e.actor,
            message: e.message, at: e.created_at }
        end if include_events
        payload
      end

      def pagination_meta(scope)
        {
          page: scope.current_page,
          per_page: scope.limit_value,
          total_pages: scope.total_pages,
          total_count: scope.total_count
        }
      end
    end
  end
end
