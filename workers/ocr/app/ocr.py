import io
from typing import Tuple

import pytesseract
from pdf2image import convert_from_bytes
from PIL import Image

from .config import CONFIG


def extract_text(blob: bytes, content_type: str | None) -> Tuple[str, dict]:
    if content_type and 'pdf' in content_type:
        images = convert_from_bytes(blob, dpi=CONFIG.ocr_dpi)
        pages = [pytesseract.image_to_string(img, lang=CONFIG.ocr_lang) for img in images]
        text = '\n\n'.join(pages)
        return text, {'pages': len(images)}

    image = Image.open(io.BytesIO(blob))
    text = pytesseract.image_to_string(image, lang=CONFIG.ocr_lang)
    return text, {'pages': 1}
