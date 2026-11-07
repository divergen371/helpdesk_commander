# 依存関係・脆弱性の監査（HC-34）

`mix.lock` と `assets/package-lock.json` の依存を、PR と週次で自動監査する。

## 監査の構成

| 対象 | コマンド | 実行場所 |
| --- | --- | --- |
| Elixir（retired パッケージ / advisory） | `mix hex.audit` | PR（audit job）、週次 |
| Elixir（GitHub Advisory） | `mix deps.audit`（`mix_audit`） | PR、週次 |
| allowlist 判定 | `mix run --no-start priv/ci/check_audit.exs` | PR、週次 |
| assets（本番依存） | `npm audit --omit=dev --audit-level=high --prefix assets` | PR、週次 |

- CI: `.github/workflows/ci.yml` の `audit` job（PR / main push）
- 週次: `.github/workflows/security-audit.yml`（毎週月曜 04:00 UTC、手動実行も可）
- 失敗時は GitHub の通知（Actions の失敗）で検知する。

## allowlist の扱い

`priv/ci/audit_allowlist.txt` に、影響しないと判断した検出だけを理由付きで残す。

```
package|version(*可)|identifier|reason|review_by(YYYY-MM-DD)
```

例:

```
cloak|1.1.4|EEF-CVE-2026-95105|AES-CTR を使用していない（Vault は AES.GCM のみ）。修正版が存在しない|2027-05-01
```

- `identifier` は advisory ID（`EEF-...`）または `retired:<package>@<version>`。
- `review_by` を過ぎるとゲートが失敗する。理由と期限の更新を強制する。
- allowlist に無い検出は失敗する。期限が近い entry と、検出に一致しなくなった entry は
  警告として表示する。
- allowlist は「除外」ではなく「影響評価の記録」。判断できないものは追加せず、修正する。

## 更新手順

1. `mix hex.outdated` で更新可能な依存を確認する。
2. 修正版がある場合は `mix deps.update <package>` で更新し、`mix quality` を通す。
3. 修正版がない、または使用していない機能の advisory だけを allowlist に追加する。
4. allowlist は 6 か月以内の `review_by` を設定する。
5. `mix hex.audit` / `mix deps.audit` / `npm audit` と
   `mix run --no-start priv/ci/check_audit.exs` をローカルで実行して確認する。

## 2026-11-07 の初回対応

- 更新: ash 3.37.3 / ash_sql 0.8.6 / ash_postgres 2.15.2 / ecto 3.14.3 /
  bandit 1.14.1 / phoenix_html 4.4.0 / assent 0.3.2 など。
- allowlist: cloak 1.1.4 の AES-CTR advisory のみ。Vault は AES.GCM を使用しており
  該当しない（Cloak 1.1.4 が最新で修正版なし）。
- 検証: 全テスト（438）通過、`mix hex.audit` の残検出は allowlist 済み 1 件のみ。
