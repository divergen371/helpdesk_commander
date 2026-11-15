# 外部ハッシュレピュテーション連携の運用手順（HC-41）

SHA256 ハッシュのみを外部フィードまたは自前フィードへ照会し、既知マルウェアを
通常スキャン前に隔離する仕組みの設計・運用手順。

## 1. 基本方針とライセンス前提

- **既定は無効**: 本番環境でも明示的に有効化しない限り外部へ照会しない。
- **ファイル本体は送らない**: 外部へ送信するのは 64 文字の SHA256 ハッシュのみ。
- **商用利用の契約条件**:
  - VirusTotal Public API や abuse.ch（MalwareBazaar）の無償 API は商用利用・
    非ファイル提供フローに制限がある。
  - 商用運用では **商用契約を結んだフィード**（VT Enterprise、MetaDefender 等）
    または **自前でホストする脅威インテリジェンス API** をエンドポイントに設定する。

## 2. 判定の優先順位

```text
ローカル deny > 外部レピュテーション infected > ローカル allow > clean キャッシュ > 通常スキャン（ClamAV / YARA）
```

- 外部レピュテーションで `infected` が返った場合、ローカル `allow` 規則や
  `clean` キャッシュよりも優先して `infected` として隔離する。
- 外部レピュテーションが `unknown` の場合は「安全」とみなさず、通常の後段判定
  （`allow` / `clean` キャッシュ / ClamAV + YARA）へ進む。

## 3. 環境変数

| 変数 | 既定 | 説明 |
| --- | --- | --- |
| `ATTACHMENT_REPUTATION_ENABLED` | `false` | `"true"` / `"1"` でグローバル有効化 |
| `ATTACHMENT_REPUTATION_URL` | なし | 照会先 URL（`{sha256}` プレースホルダ可） |
| `ATTACHMENT_REPUTATION_METHOD` | `get` | `get` または `post` |
| `ATTACHMENT_REPUTATION_API_KEY_HEADER` | なし | 認証ヘッダ名（例: `x-apikey`） |
| `ATTACHMENT_REPUTATION_API_KEY` | なし | 認証キー |
| `ATTACHMENT_REPUTATION_TIMEOUT_MS` | `3000` | HTTP タイムアウト（ミリ秒） |
| `ATTACHMENT_REPUTATION_VERDICT_PATH` | なし | JSON 判定パス（例: `data.malicious`）。未指定時は 200=`infected`, 404=`unknown` |
| `ATTACHMENT_REPUTATION_DETAIL_PATH` | なし | 判定詳細の JSON パス（例: `family`） |
| `ATTACHMENT_REPUTATION_INFECTED_TTL_SEC` | `86400` | `infected` キャッシュの保持秒数（24 時間） |
| `ATTACHMENT_REPUTATION_UNKNOWN_TTL_SEC` | `3600` | `unknown` キャッシュの保持秒数（1 時間） |

## 4. 会社単位の有効・無効化

ハッシュの照会自体が機密（未公開文書の特徴など）になり得る会社では、グローバル設定が
有効であっても会社単位で無効化できる。

- 管理画面 `/admin/attachment-rules` の「外部レピュテーション照会」から切り替え可能。
- コードからは `HelpdeskCommander.Attachments.Reputation.set_company_enabled/2` で変更する。
- **グローバル有効 かつ 会社有効** のときだけ外部へ照会し、いずれかが無効なら一切送信しない。

## 5. 障害時（fail-open）と監査ログ

- API タイムアウト、5xx、429、接続不能、不正レスポンス時は **fail-open** とし、
  既存のローカル規則および ClamAV / YARA の判定を維持する（アップロードの単一障害点にしない）。
- すべての判定（`lookup` / `cache_hit` / `disabled` / `error_fail_open` / `company_setting_updated`）は
  `Logger` に `attachment_reputation` プレフィックスで記録する。
- 障害時は `attachment_reputation error_fail_open` のログと、添付の `scan_note` に記録される
  `reputation_fail_open:` を確認する。

## 6. 誤検知時の対応

- 外部フィードの誤検知で隔離された場合は、既存の誤検知解除手順（HC-20: チケット詳細からの
  `override_infected`）で理由付きで `clean` に戻せる。
- 再アップロードが続く場合は、当該会社の外部レピュテーションを無効化するか、ローカル `deny`
  との兼ね合いを確認する。
