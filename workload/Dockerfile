# NGS pipeline worker: fastp -> bwa mem -> samtools, driven by a Redis job queue.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      fastp bwa samtools curl ca-certificates gzip \
      python3 python3-redis python3-prometheus-client \
 && rm -rf /var/lib/apt/lists/*

COPY worker.py prepare-data.sh /app/
RUN chmod +x /app/prepare-data.sh && mkdir -p /tmp/work && chown 65532:65532 /tmp/work

USER 65532:65532
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python3", "/app/worker.py"]
