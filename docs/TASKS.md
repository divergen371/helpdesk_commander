# Tasks

未完了タスクは **Backlog.md**（`backlog/`）を正本とする。
各タスクの目的・受け入れ条件・依存関係・進捗は CLI / Web UI から確認する。

## 使い方

```bash
# 一覧
backlog task list --plain

# ボード（ターミナル）
backlog board

# Web UI（ローカル）
backlog browser

# 検索・詳細
backlog search "graph" --plain
backlog task view HC-1 --plain

# 新しいタスク
backlog task create "タイトル" -d "背景" --ac "完了条件"
```

## マイルストーン

| ID | 名称 |
| --- | --- |
| M1 | MVP クローズ |
| M2 | 品質・セキュリティ |
| M3 | Incident 運用 |
| M4 | 分析・外部連携 |
| M5 | AI・意思決定支援 |

## ドキュメントの役割

- `ROADMAP.md`: フェーズ構成と方針（実行単位は Backlog.md）
- `STATUS.md`: テスト・カバレッジ・既知の制約のスナップショット
- `Walkthrough.md`: 過去の作業履歴（凍結。以後の作業記録は Backlog.md へ）
- `README.md`: 機能一覧と利用方法
- `AGENT_WORKFLOW.md`: エージェント向けの実行手順と Hermes Agent 用プロンプト
