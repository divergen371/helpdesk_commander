# .gitignore 設定ガイド

## 📋 概要

`.gitignore`は、Gitリポジトリにコミットしないファイル・ディレクトリを指定するファイルです。
機密情報、生成ファイル、環境依存ファイルを除外することで、クリーンなリポジトリを維持します。

## 🗂 現在の設定

### カテゴリ別の除外ファイル

#### 1. ビルド成果物

```gitignore
# Mix build artifacts
/_build/
/cover/
/doc/

# Compiled files
*.ez
```

**理由**: 
- これらはソースコードから生成されるため、リポジトリに含める必要がない
- 各開発者が自分の環境で生成すべき

#### 2. 依存関係

```gitignore
# Dependencies
/deps/
/assets/node_modules/
```

**理由**:
- `mix.exs`と`mix.lock`から再現可能
- サイズが大きくなりがち
- プラットフォーム依存の可能性

#### 3. 機密情報

```gitignore
# Environment variables (secrets)
.env
.env.local
.env.*.local

# Secret configuration
/config/*.secret.exs
```

**理由**:
- データベースパスワード、APIキーなどの機密情報を含む
- 環境ごとに異なる値を持つ
- **絶対にコミットしてはいけない**

**ベストプラクティス**:
- `.env.example`をテンプレートとして提供（✅済み）
- 実際の`.env`は各開発者が作成

#### 4. エディタ・IDE関連

```gitignore
# Editor files
.vscode/
.idea/
*.swp
*.swo
*~

# Elixir Language Server
/.elixir_ls/
```

**理由**:
- エディタ設定は個人の好みに依存
- チーム全体で統一する必要がない
- 頻繁に変更される

**例外**: チーム全体で使用する設定があれば含めても良い

#### 5. OS生成ファイル

```gitignore
# macOS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes

# Windows
ehthumbs.db
Thumbs.db
```

**理由**:
- OS固有のメタデータ
- プロジェクトに関係ない
- 他のOSユーザーには不要

#### 6. 開発ツール関連

```gitignore
# Dialyzer PLT files
/priv/plts/
*.plt
*.plt.hash

# VM crash dumps
erl_crash.dump

# Logs
*.log
/log/
```

**理由**:
- これらは開発中に生成される一時ファイル
- 各開発者の環境で独自に生成される

#### 7. 静的アセット

```gitignore
# Compiled assets
/priv/static/assets/
/priv/static/cache_manifest.json

# Uploads
/priv/static/uploads/
```

**理由**:
- ビルドプロセスで生成される
- 本番環境では別の方法でデプロイされる

#### 8. その他

```gitignore
# Temporary files
/tmp/
*.bak
*.backup

# Package tarballs
helpdesk_commander-*.tar

# Database files (local development)
*.db
*.db-shm
*.db-wal

# Docker volumes
/postgres_data/
```

## ⚠️ コミットしてはいけないもの

### 🔴 絶対にNG

1. **機密情報**
   - パスワード
   - APIキー
   - 秘密鍵
   - アクセストークン

2. **個人情報**
   - 本番データのダンプ
   - ユーザー情報

3. **大きなバイナリファイル**
   - ビデオ
   - 大量の画像（アセットを除く）
   - データベースダンプ

### 🟡 通常は除外

1. **ログファイル**
2. **一時ファイル**
3. **エディタ設定**
4. **OS固有ファイル**

### 🟢 コミットすべきもの

1. **ソースコード** (`.ex`, `.exs`, `.heex`)
2. **設定ファイル** (`mix.exs`, `config/*.exs`)
3. **依存関係のロックファイル** (`mix.lock`)
4. **ドキュメント** (`README.md`, `docs/`)
5. **テスト** (`test/`)
6. **マイグレーション** (`priv/repo/migrations/`)
7. **シードデータ** (`priv/repo/seeds.exs`)
8. **静的アセット** (画像、CSS、JSのソース)

## 🔍 チェックコマンド

### 除外されているファイルを確認

```bash
# .gitignoreで除外されているファイルを表示
git status --ignored

# 特定のファイルが除外されているか確認
git check-ignore -v .env
```

### 誤ってコミットされたファイルを削除

```bash
# キャッシュから削除（ファイルは残る）
git rm --cached <file>

# ディレクトリごと削除
git rm --cached -r <directory>

# 例: .elixir_lsを削除
git rm --cached -r .elixir_ls
git commit -m "Remove .elixir_ls from repository"
```

### すでにコミットされた機密情報を完全削除

**警告**: Git履歴を書き換えるため、チーム全体に影響します。

```bash
# git-filter-repoを使用（推奨）
pip install git-filter-repo
git filter-repo --invert-paths --path config/secrets.exs

# または BFG Repo-Cleaner
bfg --delete-files secrets.exs
```

## 🛠 カスタマイズ

### プロジェクト固有の除外

```gitignore
# プロジェクト固有のファイル
/my_custom_output/
*.custom_extension
```

### グローバル .gitignore

個人のエディタ設定などは、グローバル設定で除外：

```bash
# グローバル .gitignore を設定
git config --global core.excludesfile ~/.gitignore_global

# ~/.gitignore_global に個人設定を追加
echo ".vscode/" >> ~/.gitignore_global
echo ".idea/" >> ~/.gitignore_global
```

## 📊 .gitignore のパターン

### 基本パターン

```gitignore
# 特定のファイル
secret.txt

# 特定の拡張子
*.log

# ディレクトリ全体
/build/

# サブディレクトリも含む
**/temp/

# 否定パターン（例外）
!important.log
```

### 例

```gitignore
# すべての.logを除外
*.log

# ただし error.log は含める
!error.log

# ルートの config ディレクトリのみ
/config/

# すべての config ディレクトリ
**/config/
```

## 🔧 トラブルシューティング

### 問題: .gitignoreが効かない

**原因**: ファイルが既にGitの管理下にある

**解決策**:

```bash
# キャッシュをクリア
git rm -r --cached .
git add .
git commit -m "Fix .gitignore"
```

### 問題: 間違ったファイルをコミットしてしまった

**直前のコミット**:

```bash
git reset HEAD~1
# .gitignoreを修正
git add .
git commit -m "Fix .gitignore and recommit"
```

**履歴の途中**:

```bash
# インタラクティブにrebase
git rebase -i HEAD~5
# 該当コミットを edit に変更
git rm --cached <file>
git rebase --continue
```

## ✅ チェックリスト

### 新しいプロジェクト開始時

- [ ] `.gitignore`を作成（✅済み）
- [ ] `.env.example`を作成（✅済み）
- [ ] 機密情報が除外されているか確認
- [ ] `git status --ignored`で確認

### コミット前

- [ ] `git status`で確認
- [ ] 機密情報が含まれていないか確認
- [ ] ビルド成果物が含まれていないか確認

### 定期的に

- [ ] `.gitignore`が最新か確認
- [ ] 不要なファイルが増えていないか確認
- [ ] `git status --ignored`でチェック

## 📚 参考リンク

- [Git公式ドキュメント - gitignore](https://git-scm.com/docs/gitignore)
- [GitHub .gitignore テンプレート](https://github.com/github/gitignore)
- [gitignore.io](https://www.toptal.com/developers/gitignore) - カスタム.gitignore生成

## 🎯 まとめ

### ベストプラクティス

1. **早めに設定** - プロジェクト開始時に`.gitignore`を作成
2. **機密情報は絶対に除外** - `.env`、秘密鍵など
3. **生成ファイルは除外** - ビルド成果物、依存関係
4. **定期的に見直し** - プロジェクトの進化に合わせて更新

### よくあるミス

❌ `.env`をコミット
❌ `node_modules/`や`deps/`をコミット
❌ エディタ設定をコミット
❌ ログファイルをコミット

### 正しい方法

✅ `.env.example`をテンプレートとして提供
✅ `mix.lock`で依存関係を管理
✅ エディタ設定はグローバル`.gitignore`で除外
✅ ログは`.gitignore`で除外
