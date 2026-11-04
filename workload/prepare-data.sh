#!/usr/bin/env bash
# One-time data preparation for the benchmark. Produces, under $DATA_DIR:
#   ref/chr20.fa (+ bwa index)      human chr20, GRCh38, from UCSC
#   reads/sample.fastq.gz           first $READS read pairs (R1 only) of a
#                                   1000 Genomes sample (HG00096, SRR062634)
# Only the first few tens of MB of the FASTQ are downloaded: the stream is cut
# after $READS reads. All data is public.
set -euo pipefail

DATA_DIR="${DATA_DIR:-/data}"
READS="${READS:-200000}"
REF_URL="https://hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/chr20.fa.gz"
FASTQ_URLS=(
  "https://ftp.sra.ebi.ac.uk/vol1/fastq/SRR062/SRR062634/SRR062634_1.fastq.gz"
)

mkdir -p "${DATA_DIR}/ref" "${DATA_DIR}/reads"

if [[ ! -f "${DATA_DIR}/ref/chr20.fa.bwt" ]]; then
  echo "==> Downloading chr20 reference"
  curl -fsSL "${REF_URL}" | gunzip -c > "${DATA_DIR}/ref/chr20.fa"
  echo "==> Building bwa index (1-3 minutes)"
  bwa index "${DATA_DIR}/ref/chr20.fa"
else
  echo "==> Reference already prepared"
fi

if [[ ! -f "${DATA_DIR}/reads/sample.fastq.gz" ]]; then
  lines=$((READS * 4))
  for url in "${FASTQ_URLS[@]}"; do
    echo "==> Streaming first ${READS} reads from ${url}"
    set +o pipefail
    curl -fsSL "${url}" | gunzip -c 2>/dev/null | head -n "${lines}" | gzip -c > "${DATA_DIR}/reads/sample.fastq.gz"
    set -o pipefail
    got=$(gunzip -c "${DATA_DIR}/reads/sample.fastq.gz" | wc -l)
    if [[ "${got}" -eq "${lines}" ]]; then
      echo "==> Got ${READS} reads"
      break
    fi
    echo "   incomplete (${got} lines), trying next mirror"
    rm -f "${DATA_DIR}/reads/sample.fastq.gz"
  done
  [[ -f "${DATA_DIR}/reads/sample.fastq.gz" ]] || { echo "FASTQ download failed" >&2; exit 1; }
else
  echo "==> Reads already prepared"
fi

echo "==> Data ready:"
du -sh "${DATA_DIR}"/ref "${DATA_DIR}"/reads
