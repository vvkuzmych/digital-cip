import io

import boto3
from botocore.client import Config as BotoConfig

from .config import CONFIG


def s3_client():
    return boto3.client(
        's3',
        endpoint_url=CONFIG.minio_endpoint,
        aws_access_key_id=CONFIG.minio_access_key,
        aws_secret_access_key=CONFIG.minio_secret_key,
        region_name=CONFIG.minio_region,
        config=BotoConfig(signature_version='s3v4', s3={'addressing_style': 'path'}),
    )


def download_object(key: str) -> bytes:
    buffer = io.BytesIO()
    s3_client().download_fileobj(CONFIG.minio_bucket, key, buffer)
    buffer.seek(0)
    return buffer.read()
