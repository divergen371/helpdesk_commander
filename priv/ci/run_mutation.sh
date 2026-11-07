#!/usr/bin/env bash
# 高リスクモジュールに限定した変異テスト（HC-39）
#
# 各モジュールの mutation score が下限を下回ると失敗する。等価な mutant は
# ソース中の `# mutare:ignore[family] 理由` で除外する（無言の除外はしない）。
set -euo pipefail

MODULES=(
  "lib/helpdesk_commander/authorization.ex:95"
  "lib/helpdesk_commander/attachments/file_policy.ex:95"
  "lib/helpdesk_commander/support/pii_hash.ex:95"
  "lib/helpdesk_commander/support/company_code.ex:95"
)

failed=0

for entry in "${MODULES[@]}"; do
  file="${entry%%:*}"
  min_score="${entry##*:}"

  echo "== mutation: ${file} (min score ${min_score}%)"

  args=(--only "${file}" --min-score "${min_score}" --max-mutants 500)

  # PR では変更行に限定する（MUTATION_SINCE=origin/main など）。夜間・main は全量。
  if [ -n "${MUTATION_SINCE:-}" ]; then
    args+=(--since "${MUTATION_SINCE}")
  fi

  if ! MIX_ENV=test mix mutare "${args[@]}"; then
    echo "FAILED: ${file} below ${min_score}%"
    failed=1
  fi
done

if [ "${failed}" -ne 0 ]; then
  echo "mutation gate: FAILED"
  exit 1
fi

echo "mutation gate: ok"
