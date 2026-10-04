# Project Hub

開発リポジトリの進捗・作業計画を集約する独立Gitリポジトリ。

## 情報の置き場所

- `projects.yaml`: ID、remote、状態の正本。外部モジュール不要で読み書きするため、YAML 1.2で有効なJSON記法を使用する。編集時もJSON記法を維持する。
- `summary.md`: 進捗の概要。状態の正本は `projects.yaml`。
- `projects/<id>/backlog.md`: プロジェクトの作業一覧。
- `projects/<id>/tasks/`: 並列作業ごとの記録。ファイルごとに担当を分ける。
- `projects/<id>/docs/`: 検討中の仕様・横断設計。コードの版に依存する仕様は開発repoに残す。
- `local.json`: この端末のcheckout登録。Git管理対象外。

## 操作

Windows PowerShell 5.1 / PowerShell 7、Git、ローカルNTFSを使用する。
開発repoから次を実行する。`-RepoPath` で対象を明示できる。

```powershell
& C:\_project-hub\tools\project.ps1 init
& C:\_project-hub\tools\project.ps1 attach
& C:\_project-hub\tools\project.ps1 doctor
& C:\_project-hub\tools\project.ps1 detach
& C:\_project-hub\tools\project.ps1 archive
```

`init` は登録、`attach` は接続。既存データを上書きせず再実行できる。
変更操作は `-WhatIf` で確認できる。終了時は全checkoutをdetachしてからarchiveする。
archiveは状態とコードcommitを記録し、資料・コードは削除しない。再開は登録状態を確認してactiveに戻す。
detach後もローカルの `/.dev` 除外設定は維持する。

`{PATH疎通済みのディレクトリ}/project.cmd` が利用できれば `project attach` の形で呼べる。
入口は環境変数 `PROJECT_HUB_HOME` を優先する。
hub移動後は旧接続をdetachし、設定変更後にattachする。

追加worktreeでは `attach -RepoPath <path> -Id <既存ID>` を実行する。
