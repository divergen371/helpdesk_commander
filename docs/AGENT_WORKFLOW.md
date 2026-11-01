# エージェント向けタスク運用（Backlog.md）

このリポジトリの未完了タスクは **Backlog.md**（`backlog/`）を正本とする。
Claude Code / Codex / Hermes Agent など、どのエージェントでも同じ手順で動く。

## 最初にやること

会話の開始時に一度だけ実行する。

```bash
backlog instructions overview
```

タスクの作成・分解を行う前:

```bash
backlog instructions task-creation
```

実装・ステータス変更・計画の記録を行う前:

```bash
backlog instructions task-execution
```

完了判定・最終サマリ・Done へ移す前:

```bash
backlog instructions task-finalization
```

`backlog` が見つからない場合:

```bash
brew install backlog-md   # 1.55.3 で動作確認
```

## 正本とドキュメントの役割

| 対象 | 役割 |
| --- | --- |
| `backlog/tasks/hc-*.md` | 未完了タスクの正本（CLI 経由で更新） |
| `backlog/milestones/` | M1〜M5 のマイルストーン |
| `docs/ROADMAP.md` | フェーズ構成と方針。タスクの状態は持たない |
| `docs/STATUS.md` | テスト・カバレッジ・既知の制約のスナップショット |
| `docs/Walkthrough.md` | 過去の作業履歴（凍結） |
| `README.md` | 機能一覧と利用方法 |
| `docs/TASKS.md` | Backlog.md の使い方 |

**Backlog の Markdown を直接編集しない。** 必ず `backlog` CLI を使う。

## 1セッションの流れ

1. **探す**: 既存タスクを検索する
   ```bash
   backlog search "graph" --plain
   backlog task list --plain
   ```
2. **選ぶ**: 1セッションにつき1タスクだけ選ぶ
   ```bash
   backlog task view HC-1 --plain
   ```
3. **開始する**: ステータスを In Progress にし、必要なら担当を設定
   ```bash
   backlog task edit HC-1 -s "In Progress" -a @hermes
   ```
4. **計画する**: コードベースを調査し、実装計画をタスクへ記録
   ```bash
   backlog task edit HC-1 --notes "調査結果と実装方針"
   ```
5. **実装する**: 小さくコミットする。無関係な変更を混ぜない
6. **検証する**
   ```bash
   mix precommit
   mix coveralls.json
   mix dialyzer
   ```
7. **受け入れ条件を確認する**
   ```bash
   backlog task edit HC-1 --check-ac 1
   backlog task edit HC-1 --check-ac 2
   ```
8. **完了する**: 最終サマリを書き、Done へ移す
   ```bash
   backlog task edit HC-1 --final-summary "変更点と検証結果" -s Done
   ```

## マイルストーン

| ID | 名称 | 主なタスク |
| --- | --- | --- |
| M1 | MVP クローズ | HC-1 |
| M2 | 品質・セキュリティ | HC-2, HC-10, HC-12, HC-14 |
| M3 | Incident 運用 | HC-3 |
| M4 | 分析・外部連携 | HC-4, HC-5, HC-6, HC-7, HC-8, HC-9, HC-11, HC-15 |
| M5 | AI・意思決定支援 | HC-13 |

## ルール

- 1セッション1タスク。複数タスクを同時に進めない。
- 新しい作業は、まず既存タスクを検索し、重複がなければ `backlog task create` で作る。
- 受け入れ条件は「利用者から見て何が真になるか」で書く。実装手順は書かない。
- 実装計画はタスク開始後に書く。作成時に speculative な計画を書かない。
- ステータスは CLI で変更する。`To Do` → `In Progress` → `Done`。
- 完了時は `mix precommit` を通し、カバレッジ 80% 以上を維持する。
- ユーザーが明示しない限り、コミット・push は行わない。
- 日本語で報告する。ファイルパスは正確に示す。
- 既存の `docs/` の役割を崩さない。作業履歴を `Walkthrough.md` に追記しない。

## Hermes Agent への初期プロンプト例

```text
このリポジトリのタスク管理は Backlog.md です。
最初に `backlog instructions overview` と `backlog instructions task-execution` を実行し、
`docs/AGENT_WORKFLOW.md` の手順に従ってください。
未完了タスクは `backlog task list --plain` で確認できます。
今回は HC-1 のみを進め、開始時に In Progress へ変更してください。
実装計画はタスクの notes に書き、完了時に受け入れ条件を確認して Done にしてください。
```
