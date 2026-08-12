# Meeting Insight

会議中の「たしかこうだった」を、話題が移る前に「このコミットのこの実装ではこう」へ変える、macOS向けの実装検証アシスタント構想です。

会議前にコードリポジトリとローカルWiki directoryを名前付きResearch Scopeとして登録し、選択したscope内のsourceだけを調査・引用します。

プロダクト判断、Web調査、推奨アーキテクチャ、データ契約は [プロダクト・技術設計書](docs/product-architecture.md) を参照してください。実装順序、モジュール境界、Work package、受け入れ条件は [詳細実装計画](docs/implementation-plan.md) にまとめています。

実装は期間見積もりではなく、test・architecture・privacy・citation integrityを適応度関数としてHarnessで検証し、hard gateを満たすまで小さい変更を反復するLoop engineeringで進めます。

現時点は設計フェーズです。最初の実装は、macOS 26以上を対象にしたメニューバーアプリと、同じコアを使う開発用CLIを想定しています。
