# Meeting Insight

会議中の「たしかこうだった」を、話題が移る前に「このコミットのこの実装ではこう」へ変える、macOS向けの実装検証アシスタント構想です。

会議前にコードリポジトリとローカルWiki directoryを名前付きResearch Scopeとして登録し、選択したscope内のsourceだけを調査・引用します。

プロダクト判断、Web調査、推奨アーキテクチャ、データ契約は [プロダクト・技術設計書](docs/product-architecture.md) を参照してください。実装順序、モジュール境界、Work package、受け入れ条件は [詳細実装計画](docs/implementation-plan.md) にまとめています。

実装は期間見積もりではなく、test・architecture・privacy・citation integrityをHarnessで検証し、hard gateを満たすまで小さい変更を反復するLoop engineeringで進めます。

現在はWP-01まで実装済みです。macOS 26以上を対象にしたメニューバーアプリ、同じコアを使う開発用CLI、Domain contract、version 1のInsight Card schema、依存境界を検証するHarnessを含みます。

## Build

前提はXcode 26.3とSwift 6.2です。署名なしの初回buildとtestは次の入口で確認できます。

```sh
Scripts/bootstrap.sh
Scripts/check.sh
Scripts/check.sh build
Scripts/check.sh test
Scripts/check.sh cli
```

引数なしの `Scripts/check.sh` は、build、schema contractを含む全test、dependency architecture、privacy lintを実行し、結果を `.artifacts/checks/latest.json` に保存します。引数付きのcommandは個別確認用です。
