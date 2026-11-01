# 検索・フィルタ・ソート仕様

画面の一覧で共通に使う検索・フィルタ・ソートの約束を定める。

## 共通ルール

- 条件は URL クエリパラメータで表現し、再読み込み・共有・戻る操作で再現できる。
- 値が空文字または未定義の条件は「指定なし」として扱う。
- 許可リストにない値は無視し、既定値へフォールバックする。
- 並び順の既定は「新しい順」（`sort=newest`）。既定値は URL に含めない。
- 検索語 `q` は前後空白を除去し、最大 100 文字に切り詰める。
- 部分一致は大文字小文字を区別しない。`%` `_` `\` はエスケープする。
- 会社境界は Domain 層の `company_id` フィルタで必ず適用する。
- 暗号化済み属性は DB 検索できないため、対象外とする。

## チケット一覧（`/tickets`）

| パラメータ | 値 | 既定 |
| --- | --- | --- |
| `q` | 件名の部分一致、または Public ID の完全一致 | なし |
| `status` | `new` / `triage` / `in_progress` / `waiting` / `resolved` / `verified` / `closed` | すべて |
| `priority` | `p1` / `p2` / `p3` / `p4` | すべて |
| `type` | `question` / `incident` / `request` | すべて |
| `assignee_id` | ユーザー ID または `unassigned` | すべて |
| `sort` | `newest` / `oldest` / `priority` / `status` | `newest` |
| `page` | 1 以上の整数（20 件/ページ） | 1 |

- `description` は暗号化されているため検索対象外。件名と Public ID のみ。
- 外部ユーザーは自分のチケットに限定される（Domain 層で付与）。

## タスク一覧（`/tasks`）

| パラメータ | 値 | 既定 |
| --- | --- | --- |
| `q` | タイトルの部分一致 | なし |
| `status` | `todo` / `in_progress` / `done` | すべて |
| `priority` | `low` / `medium` / `high` | すべて |
| `assignee_id` | ユーザー ID または `unassigned` | すべて |
| `sort` | `newest` / `oldest` / `priority` / `status` / `due_date` | `newest` |

- 期限なしのタスクは `due_date` ソートで末尾に回る（PostgreSQL の NULLS LAST 相当の既定動作に従う）。

## 製品一覧（`/products`）

| パラメータ | 値 | 既定 |
| --- | --- | --- |
| `q` | 名称の部分一致 | なし |

- 並び順は名称の昇順で固定。

## 通知一覧（`/notifications`）

| パラメータ | 値 | 既定 |
| --- | --- | --- |
| `filter` | `all` / `unread` | `all` |

- 並び順は受信日時の降順で固定。

## 対象外

- 暗号化済みの本文・表示名に対する全文検索。
- 複数条件の保存（保存ビュー）。
- 横断検索（チケット・タスク・製品をまたぐ検索）。
