# ADR-0001: ScreenCaptureKit Gate A

- Status: Pending hardware evidence
- Work package: WP-08
- Decision date: Pending

## Context

Meeting Insightは、ユーザーが明示的に選択したZoomアプリの音声と自分のマイクを別sourceで取得し、同じ時刻軸で後段へ渡す必要がある。映像frameとraw audioは保存・処理せず、Stop後にScreenCaptureKit streamを残さない。Gate Aは、この前提をMac実機のZoomテスト会議で確認する。

## Environment

| Item | Value |
| --- | --- |
| Hardware | Mac mini (Mac14,3), Apple M2, 16 GB |
| macOS | 26.5.2 (25F84) |
| Xcode | 26.3 (17C529) |
| macOS SDK | 26.2 |
| Zoom | 7.0.6 (84834) |
| Base revision | `204bfbbfcd910d70ae70eda4bced53690bce9f45` |
| Measurement start | Pending |
| Measurement end | Pending |
| Background duration | Pending; target 30 minutes |

## Procedure

1. Macを手動でunlockし、Zoomのテスト会議へ参加する。
2. Meeting Insightでデータ境界を確認し、実行中アプリ一覧からZoomを選ぶ。
3. OSのScreen RecordingとMicrophone権限を確認してGate Aを開始する。
4. 相手側から音声を流し、自分のマイクでも発話する。
5. Zoomをbackgroundにしたまま30分継続する。
6. 30分後の両meter、timestamp overlap、frame count、RSS range、memory trend、capture indicatorを記録する。
7. Stop後に両meterが0へ戻り、capture indicatorとstreamが終了することを確認する。

## Evidence

### Preflight observation

2026-08-14 22:05 JSTの最初の実機確認では、Zoom公式テスト会議へ接続し、`Pebble V3` へのspeaker testでZoomの出力level 3を確認した。一方、Audio MIDI設定に表示された入力は `Microsoft Teams Audio`（Virtual、入力1 / 出力1）だけで、Zoomが列挙した2候補も「システムと同じ」と同じvirtual deviceだった。どちらも入力level 0であり、「自分のマイクmeterが動く」は未検証のままである。物理microphoneをmacOSのdefault inputとZoomのinputへ設定して再実行する。

同じpreflightで、`LSUIElement` とlaunch直後1回だけのwindow探索によりmain windowを前面操作できない状態を再現した。regular activation policy、built plistの `LSUIElement=false`、20回・50 ms間隔のbounded window activation retryを追加し、App shell test 5件と `PRIVACY-USAGE-001` で固定した。この修正はcapture hardware evidenceの代替ではない。

### Automated checks

- `CAPTURE-SDK-001`: macOS 26.2 SDKで `.audio` と `.microphone` の別outputを確認済み。
- `CAPTURE-AUDIO-001`: 両source、PCM meter、timestamp overlap、30分条件、memory trend、継続memory増加50 MiB未満、Stop cleanupを決定的testで確認済み。
- `ARCH-AUDIO-001`: CaptureからUI/Researchへの依存とvideo output登録を禁止。
- `PRIVACY-USAGE-001`: built appのScreen Recording、Audio Capture、Microphone用途説明を確認済み。
- App shell tests: capture開始がmain actorをblockせず、Stopをserviceへ転送することを確認済み。

### Hardware observations

| Gate A item | Observation | Result |
| --- | --- | --- |
| 選択したZoomアプリ音声だけを取得 | Pending | Pending |
| Zoom相手音声meter | Pending | Pending |
| 自分のマイクmeter | Pending | Pending |
| app audio/microphone timestamp overlap | Pending | Pending |
| background 30分、クラッシュなし | Pending | Pending |
| RSS min/maxと継続増加の有無 | Pending | Pending |
| video frameを登録・保存・処理しない | Static gate passed; hardware indicator scope pending | Pending |
| Stop後にindicatorとstreamが終了 | Pending | Pending |
| 権限説明と実際の取得範囲が一致 | Pending | Pending |

## Decision

Pending。hardware observationsがすべてPassになるまでWP-08を完了扱いにせず、WP-09へ進まない。

## Failure routes

- マイクだけ不安定なら `AVAudioEngineMicrophoneSource` へ分離する。
- Zoom app filterが不安定ならsystem content-sharing pickerを採用する。
- app音声取得が不可能なら手動テキスト＋マイクのみを開発継続用fallbackにするが、`v0.1.0`公開判定は保留する。
