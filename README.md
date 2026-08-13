# Meeting Insight

会議中の「たしかこうだった」を、話題が移る前に「このコミットのこの実装ではこう」へ変える、macOS向けの実装検証アシスタント構想です。

会議前にコードリポジトリとローカルWiki directoryを名前付きResearch Scopeとして登録し、選択したscope内のsourceだけを調査・引用します。

プロダクト判断、Web調査、推奨アーキテクチャ、データ契約は [プロダクト・技術設計書](docs/product-architecture.md) を参照してください。実装順序、モジュール境界、Work package、受け入れ条件は [詳細実装計画](docs/implementation-plan.md) にまとめています。

実装は期間見積もりではなく、test・architecture・privacy・citation integrityをHarnessで検証し、hard gateを満たすまで小さい変更を反復するLoop engineeringで進めます。

現在はWP-07まで実装済みです。macOS 26以上を対象にしたメニューバーアプリは、Research Scopeの作成と切り替え、利用sourceとプライバシー境界の事前確認、Codex doctor、手入力調査、実行中のCancel、検証済みInsight Card表示を提供します。アプリと `doctor` / `scope` / `snapshot` / `validate` / `ask` CLIは同じコアpipelineを使います。質問はResearch Scopeのsnapshot、scope限定のlocal knowledge抜粋、AgentEngine、citation再検証を通り、検証済みcardだけをfile・line・commit付きで出力します。Codex CLIはshell非経由のread-only・ephemeral processとして起動し、JSONLと最終cardをfail-closedにdecodeします。CIでは外部通信のないrecorded fake engineで3つのDemoRepo質問を再現し、実Codex integrationは明示的なopt-inにしています。

## Build

前提はXcode 26.3とSwift 6.2です。署名なしの初回buildとtestは次の入口で確認できます。

```sh
Scripts/bootstrap.sh
Scripts/check.sh
Scripts/check.sh build
Scripts/check.sh test
Scripts/check.sh fixture
Scripts/check.sh cli
Scripts/check.sh vertical-slice
Scripts/check.sh app-service
Scripts/check.sh app-shell
```

引数なしの `Scripts/check.sh` は、build、schema contractを含む全test、Demo fixture contract、dependency architecture、privacy lintを実行し、結果を `.artifacts/checks/latest.json` に保存します。fixtureを使うreportにはDemoRepoのcommit SHAとDemoWikiのcontent revisionも記録します。引数付きのcommandは個別確認用です。

`Scripts/make-demo-repo.sh <output-path>` は、Feature Aのplan条件・test・設定を含む独立Git repositoryを生成します。`Fixtures/questions.json` と `Fixtures/ExpectedCards/` は `verified`、`contradicted`、`not_found` の正答を1件ずつ固定しています。
