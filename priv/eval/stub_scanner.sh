#!/usr/bin/env bash
# 評価用の決定的なスタブスキャナ（HC-26）。
# EICAR を含むファイルを infected（exit 1）とし、それ以外を clean（exit 0）とする。
# 実際の検出力ではなく、評価ハーネスとコーパスの回帰を CI で確認するために使う。
set -euo pipefail

target=""
for arg in "$@"; do
  target="$arg"
done

if [ -z "$target" ] || [ ! -f "$target" ]; then
  echo "stub scanner: missing target" >&2
  exit 2
fi

# 検査時間の計測が 0ms にならないよう、ごく短い遅延を入れる
sleep 0.005

if [[ "$target" == *.zip ]]; then
  if unzip -p "$target" 2>/dev/null | grep -aq "EICAR"; then
    echo "Eicar-Test-Signature FOUND"
    exit 1
  fi
else
  if grep -aq "EICAR" "$target"; then
    echo "Eicar-Test-Signature FOUND"
    exit 1
  fi
fi

exit 0
