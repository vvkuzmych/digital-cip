from typing import List

from sentence_transformers import SentenceTransformer

from .config import CONFIG
from .logger import LOG

_model: SentenceTransformer | None = None


def model() -> SentenceTransformer:
    global _model
    if _model is None:
        LOG.info('embedder.model.loading', extra={
            'event': 'embedder.model.loading', 'model': CONFIG.embedding_model,
        })
        _model = SentenceTransformer(CONFIG.embedding_model)
        dim = _model.get_sentence_embedding_dimension()
        if dim != CONFIG.embedding_dim:
            LOG.warning('embedder.dim.mismatch', extra={
                'event': 'embedder.dim.mismatch',
                'model_dim': dim, 'configured_dim': CONFIG.embedding_dim,
            })
        LOG.info('embedder.model.loaded', extra={
            'event': 'embedder.model.loaded', 'model': CONFIG.embedding_model, 'dim': dim,
        })
    return _model


def embed_batch(texts: List[str]) -> list[list[float]]:
    vectors = model().encode(
        texts,
        batch_size=CONFIG.batch_size,
        show_progress_bar=False,
        normalize_embeddings=True,
        convert_to_numpy=True,
    )
    return [v.tolist() for v in vectors]
