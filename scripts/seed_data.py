#!/usr/bin/env python3
"""Generate Parquet fixtures and upload them to MinIO (S3-compatible)."""

from __future__ import annotations

import datetime
import io
import os
import sys

import boto3
import pyarrow as pa
import pyarrow.parquet as pq

ENDPOINT = os.environ.get("S3_ENDPOINT", "http://localhost:9000")
ACCESS_KEY = os.environ.get("MINIO_ACCESS_KEY", os.environ.get("AWS_ACCESS_KEY_ID", "minio"))
SECRET_KEY = os.environ.get("MINIO_SECRET_KEY", os.environ.get("AWS_SECRET_ACCESS_KEY", "minio123"))
RAW_BUCKET = os.environ.get("RAW_BUCKET", "lakehouse-raw")
WAREHOUSE_BUCKET = os.environ.get("WAREHOUSE_BUCKET", "lakehouse-warehouse")


def s3_client():
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        region_name=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"),
    )


def ensure_bucket(client, bucket: str) -> None:
    try:
        client.head_bucket(Bucket=bucket)
    except client.exceptions.ClientError:
        client.create_bucket(Bucket=bucket)


def upload_table(client, bucket: str, prefix: str, table: pa.Table) -> None:
    buffer = io.BytesIO()
    pq.write_table(table, buffer)
    buffer.seek(0)
    key = f"{prefix.rstrip('/')}/data.parquet"
    client.put_object(Bucket=bucket, Key=key, Body=buffer.getvalue())
    print(f"Uploaded s3://{bucket}/{key}")


def main() -> int:
    orders = pa.table(
        {
            "order_id": pa.array([1, 2, 3, 4], type=pa.int64()),
            "customer_id": pa.array([101, 102, 101, 103], type=pa.int64()),
            "order_date": pa.array(
                [
                    datetime.date(2024, 1, 1),
                    datetime.date(2024, 1, 2),
                    datetime.date(2024, 1, 3),
                    datetime.date(2024, 1, 4),
                ],
                type=pa.date32(),
            ),
            "amount": pa.array([10.5, 25.0, 15.75, 42.0], type=pa.float64()),
        }
    )

    customers = pa.table(
        {
            "customer_id": pa.array([101, 102, 103], type=pa.int64()),
            "customer_name": pa.array(["Ada", "Bob", "Cara"], type=pa.string()),
            "country": pa.array(["EE", "FI", "LV"], type=pa.string()),
        }
    )

    client = s3_client()
    ensure_bucket(client, RAW_BUCKET)
    ensure_bucket(client, WAREHOUSE_BUCKET)
    upload_table(client, RAW_BUCKET, "parquet/orders", orders)
    upload_table(client, RAW_BUCKET, "parquet/customers", customers)
    return 0


if __name__ == "__main__":
    sys.exit(main())
