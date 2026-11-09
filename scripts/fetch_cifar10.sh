#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${1:-$ROOT_DIR/datasets/cifar10}"
URL="${CIFAR10_URL:-https://www.cs.toronto.edu/~kriz/cifar-10-binary.tar.gz}"
ARCHIVE="$DATA_DIR/cifar-10-binary.tar.gz"

mkdir -p "$DATA_DIR"

echo "[cifar10] download url: $URL"
echo "[cifar10] target dir : $DATA_DIR"

if [[ ! -f "$ARCHIVE" ]]; then
  curl -L --fail --retry 4 --retry-delay 2 "$URL" -o "$ARCHIVE"
else
  echo "[cifar10] archive already present: $ARCHIVE"
fi

if [[ ! -d "$DATA_DIR/cifar-10-batches-bin" ]]; then
  tar -xzf "$ARCHIVE" -C "$DATA_DIR"
else
  echo "[cifar10] extracted directory already present"
fi

for req in data_batch_1.bin data_batch_2.bin data_batch_3.bin data_batch_4.bin data_batch_5.bin test_batch.bin batches.meta.txt; do
  if [[ ! -f "$DATA_DIR/cifar-10-batches-bin/$req" ]]; then
    echo "[cifar10] ERROR: missing $req after extract" >&2
    exit 1
  fi
done

echo "[cifar10] ready: $DATA_DIR/cifar-10-batches-bin"
