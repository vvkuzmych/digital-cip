import logging
import sys

from pythonjsonlogger import jsonlogger

from .config import CONFIG


def configure_logging() -> logging.Logger:
    logger = logging.getLogger(CONFIG.service_name)
    if logger.handlers:
        return logger

    level = getattr(logging, CONFIG.log_level.upper(), logging.INFO)
    logger.setLevel(level)

    handler = logging.StreamHandler(sys.stdout)
    formatter = jsonlogger.JsonFormatter(
        '%(asctime)s %(levelname)s %(name)s %(message)s',
        rename_fields={'asctime': 'ts', 'levelname': 'level', 'name': 'service'}
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.propagate = False
    return logger


LOG = configure_logging()
