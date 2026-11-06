# NGS pipeline worker: fastp -> bwa mem -> samtools, driven by a Redis job queue.
#
# Build args:
#   DATA_DIR  default data mount (default /data). Building with a non-existent
#             path (e.g. --build-arg DATA_DIR=/nonexistent) yields an image whose
#             jobs all fail; used by the progressive-delivery experiment (E2).
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      fastp bwa samtools curl ca-certificates gzip \
      python3 python3-redis python3-prometheus-client \
 && rm -rf /var/lib/apt/lists/*

COPY worker.py prepare-data.sh /app/
RUN chmod +x /app/prepare-data.sh && mkdir -p /tmp/work && chown 65532:65532 /tmp/work

ARG DATA_DIR=/data
ENV DATA_DIR=${DATA_DIR}
USER 65532:65532
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python3", "/app/worker.py"]
