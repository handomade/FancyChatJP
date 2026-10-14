# FancyChat JP

[Arielfy 氏の FancyChat](https://github.com/ariel-logos/Fancychat) の日本語向けフォークです。

Ashita 用のチャット置換アドオンです。FFXI 標準チャットの代わりに、タブ分け・戦闘ログの短縮・色分け・マップ検索などを備えたオーバーレイを出します。このフォークでは、**日本語クライアント**での表示・折り返し・設定画面の日本語化に加え、日本語ログ向けの色判定や DualShock など DirectInput パッドへの対応を足しています。

| | |
| --- | --- |
| オリジナル | [Arielfy / FancyChat](https://github.com/ariel-logos/Fancychat) `1.0.260721R` |
| このフォーク | [handomade / FancyChatJP](https://github.com/handomade/FancyChatJP) |
| 作者 | オリジナル: Arielfy　／　JP: Hando |
| バージョン | オリジナル `1.0.260721R`　／　JP `1.1.6`（FancyChatJP 独自採番） |

動作確認は CatsEyeXI と VanaCore の、日本語クライアントです。本家の機能はそのまま使えるようにしつつ、JP 向けの差分だけを足しています。バージョンは本家の日付付き番号（例: `1.0.260721R`）に合わせず、このフォークだけで上げます。

---

## 何ができるか（本家の機能）

- **タブ** — 全て / 戦闘 / リンクスhell / パーティ / Tell / シャウト / カスタム。戦闘を「全て」から外すと AllAlt になります
- **コンパクト戦闘ログ** — 攻撃・魔法などを短いアイコン行にまとめる（同梱の `gameicons.ttf`）
- **名前の色分け** — 自分 / パーティ / 敵 / NPC など
- **タイムスタンプ** — 行ごと、または一定間隔の区切り行
- **自動非表示** — 放置でフェード、新しいメッセージやスクロール、チャット入力で復帰（マウスホバーだけでは復帰しません）
- **BigMode** — 履歴を大きく表示するオーバーレイ
- **ホバープレビュー** — オートトランスレートのアイテム / アビリティ / 魔法
- **クリック操作** — 行のコピー、Shift でメモ、Ctrl でゾーン検索、URL の `[link]`
- **ゾーン検索とマップ** — ゾーン名を含む行を Ctrl+クリック。`/sea`、**用語辞典（wiki.ffo.jp）**、FFXIclopedia、bg-wiki、同梱マップ
- **ログ保存** — タブごとにファイルへ書き出し
- **通知音** — Tell 着信、キーワード
- **戦闘フィルタ** — キーワードで行を隠す
- **ゲームパッド** — タブ切替やスクロール（設定のゲームパッドタブ）
- **ゲーム内マニュアル** — `/fchat manual`

詳しい本家ドキュメントは [オリジナル README](https://github.com/ariel-logos/Fancychat) と、本家リポジトリの [`docs/`](https://github.com/ariel-logos/Fancychat/blob/main/docs/Home.md) を参照してください。

---

## このフォークで足したもの

### 日本語表示

日本語は **チャット本文** と **設定画面・タブ（ImGui）** で経路が違います。片方だけ直しても、もう片方は変わりません。

- **チャット本文** — GDI（既定 Meiryo）。Shift-JIS → UTF-8 と、全角幅を考慮した折り返し（`cjkWidthRatio`）。`boot.ini` は使いません
- **設定・タブ** — 文言は日本語化済み。CatsEyeXI では当初から ImGui も日本語です。文字そのものは Ashita 既定フォントに日本語が無いと `?` になります。1.1.6 は boot を使わず、起動時に Windows の Meiryo / MS Gothic / Yu Gothic を読んで ImGui に足します（VanaCore と CatsEye の両方）。メイリオは再配布できないので、アドオンに `resources/fonts` も `meiryo.ttc` も入っていません
- 日本語ログでも、入手・経験値・戦闘短縮などの**文言ベースの色**が乗るようパターンを追加（本家は英語メッセージ前提だったため、日本語ではドロップ色などが効かないことがありました）

タブがすでに日本語なら、ImGui 側は何もしません。チャットは出るのにタブが `?` のときは、下の「設定画面が `?` のとき」を見てください。

### 第2チャットウィンドウ

- ウィンドウ2の「全て」タブだけ戦闘を外すチェック（ウィンドウ1の戦闘タブと組み合わせやすい）
- Extra 側の「全てから戦闘を隠す」は、従来どおり両ウィンドウに効きます

### BigMode とゲームパッド

- BigMode 中、**修飾ボタン＋上下**でマウスホイールと同じ履歴スクロールです（押しっぱなし可）
- 第2ウィンドウが有効なら、**修飾ボタン＋左右**でウィンドウ1 / ウィンドウ2の履歴を切り替えます（タイトルに `W1` / `W2`）
- チャット入力を開いている間の左右は、本家どおりプリセットコマンドの巡回です
- **DirectInput**（DualShock など）では、十字キーはデジタルボタンではなく **ボタン32のハット（角度）** です。左 27000 / 右 9000 / 離すと -1。Xbox の D-pad 番号（2 / 3）には割り当て直しても反応しません。ハットは自動で左右として使います
- L2 などハット以外のボタンは、これまでどおり番号で取れます（例: L2 が 54）。割り当て待ちで十字キーを押すと `ハット 左` のように表示されます

GamepadNav をオンにし、修飾ボタン（初期値は LB。DirectInput では自分のパッドに取り直してください）を押しながら操作します。

### 用語辞典と Wiki（1.0.1）

ゾーン検索と GuideMe から、日本語の **用語辞典（wiki.ffo.jp）** を使えます。

- **ゾーン検索**（ゾーン名のある行を Ctrl+クリック）の先頭に「用語辞典で開く」があります。記事が `/html/数字.html` なので、英語ゾーン名でサイトのタイトル検索を開きます
- 日本語クライアントでも、FFXIclopedia / bg-wiki / 同梱 `maps/` は英語名で引きます（日本語名のままだと届きません）
- **GuideMe** に `wiki.ffo.jp` の URL を貼ると、Walkthrough 節が無いので本文を出します。本文の青いリンクはこのパネル内で次のページを開きます。**戻る** で履歴を辿れます。固定中でも URL 入力とリンク操作ができます。自動非表示は GuideMe / メモ上の操作中は止まります。
- **`/fchat ffo <検索語>`** で、用語辞典本体と同じ `search.cgi` のタイトル検索を行い、ヒット一覧を GuideMe に出します。行をクリックするとその記事をパネル内で開きます。日本語は CP932、英語名はそのまま送るので、`東ロンフォール` でも `East Ronfaure` でも検索できます
- GuideMe の行が横に入り切らないときは折り返さず、**横スクロールバー**で読めます

### チャット翻訳（1.1.0）

Say / Tell / PT / LS など、**本文がすべて半角英数**の行を日本語にします。設定の **翻訳** タブでオンにし、サイト（MyMemory 無料、DeepL、ChatGPT、Gemini）を選びます。有料 API はキーを入れるとそのサイトを使います。

- `{Name}` / `｛Name｝` と、コロンより前の話者名は原文のまま残します（スペース入りの名前も文字数で大凡判定）
- `[PartyFinder]` など他アドオンの `[名前]` 付き行は訳しません
- 同じ原文は辞書に残し、次からはネットに問い合わせません。連続ログは数件まとめて投げます
- パーティ名・自分の名前・英語ゾーン名は訳さないようにできます。知らない人名までは自動では判別できません
- `/fchat translate` でオン／オフ

### 日本語ログとクリップボード（1.0.2）

- チャット行のコピーは Unicode と CP932 の両方をクリップボードへ入れる。貼り付けと `/echo` の確認メッセージが UTF-8 のまま CP932 扱いされて文字化けしないようにした
- 戦闘の「は、」が次の名前や魔法名に残らないようにし、入手行はアイテムから「！／を手に入れた」まで入手色にする
- パーティ名は後ろがスペースでなくても色を付ける。折り返しは UTF-8 文字の途中で切らない
- 短縮戦闘の `[エアロ]` など短い魔法名が、バイト長の英語折り返し判定で次の行に落ちないようにした

### コマンドの追加

| コマンド | 内容 |
| --- | --- |
| `/fchat cjkratio [1.50-2.00]` | 全角 / 半角の折り返し比率 |
| `/fchat ffo <検索語>` | 用語辞典タイトル検索（GuideMe） |
| `/fchat translate` | チャット翻訳のオン／オフ |

---

## インストール

CatsEyeXI には本家 FancyChat（`0.9.xxxxxx` / Arielfy）が入っていることがあります。**フォルダごと消してから** FancyChatJP を置いてください。途中のファイルだけ上書きすると、本家の `fancychat.lua` と JP の `lib/` が混ざって `ApplyWindowTabBuffer` などのエラーになります。

導入はクライアントで分かれます。**CatsEyeXI では下の VanaCore zip は使いません。**

### CatsEyeXI

現在の版は **1.1.6** です。[リポジトリの `main`](https://github.com/handomade/FancyChatJP) から入れてください。CatsEye の ImGui 日本語は当初からです。VanaCore 向けのフォント登録が入ったあと、一部の CatsEye 環境でタブが `?` になることがあったので、1.1.6 は boot に頼らず Windows のフォントを直接読むようにしています。

1. ゲームを終了する
2. `Ashita/addons/fancychat` をフォルダごと削除する
3. FancyChatJP **1.1.6 以降**を `Ashita/addons/fancychat` に置く（ZIP なら中の `fancychat.lua` がこのフォルダの直下にあること。`FancyChatJP-main/fancychat.lua` のまま一段深いと読みません）
4. ランチャーの **ADDONS** で FancyChat の **Ignore Updates** にチェックを付ける（下の節）
5. ゲームを起動し、必要なら:

```
/addon load fancychat
```

読み込み行は **`fancychat version: 1.1.6 - by: Hando`** です。`1.1.5` や `0.9.xxxxxx - by: Arielfy` のままなら、まだ古いファイルです。

6. 自動起動するなら、Ashita の default スクリプトの**末尾付近**に `/addon load fancychat` を追加する。ほかのチャット系アドオンより後が安全です

起動後は `/fchat settings` で設定、`/fchat manual` でゲーム内説明です。インストール先が `C:\Games\CatsEyeXI` でも問題ありません。チャット本文が日本語で、設定のタブも日本語なら完了です。タブだけ `?` なら「設定画面が `?` のとき」へ。

#### Ignore Updates（必須）

ランチャーは公式アドオンとして本家 FancyChat を配っています。**Ignore Updates が外れていると、アドオン更新のたびに JP の Lua が本家（`0.9` / Arielfy）で上書き**されます。混ざると `ApplyWindowTabBuffer` が無い、といったエラーになります。

1. ランチャーの **ADDONS** タブを開く
2. FancyChat の **Ignore Updates** にチェックを付ける
3. 保存先はランチャーと同じフォルダの `cexi_settings.json` で、`"IgnoreUpdatesAddons"` に `fancychat` が入ります

チェックを付けなくても上書きされないことがあります（フォルダが FancyChatJP の別 git になっている、まだ FancyChat の更新が来ていない、など）。**保証ではない**ので、JP を使うならチェックは付けてください。JP をやめて本家に戻すときだけ外します。

`cexi_settings.json` の `"ResetIniFiles"` は **`true` のまま**です。フォント用に `false` にしないでください。ランチャーは起動のたびに `Ashita/config/boot/catseyexi.ini` を作り直します（ファイル名は `boot.ini` ではありません）。解像度や接続設定のためで、想定どおりです。ここを切ると、壊れた ini のまま起動できなくなることがあります。

### VanaCore

VanaCore で設定画面などの ImGui を日本語にする一式です。アドオン本体ではありません。すでに入っている FancyChatJP（**1.1.6 以降**）と XIUIJP の上へ、必要なファイルだけ重ねます。**CatsEyeXI では使いません。**

ダウンロード: [VanaCore.zip](https://github.com/handomade/FancyChatJP/releases/download/1.1.4/VanaCore.zip)（[Releases](https://github.com/handomade/FancyChatJP/releases)）。解凍すると `VanaCore日本語セットアップ` フォルダになります。

1. VanaCore と Ashita を終了する
2. zip を解凍し、そのフォルダを **Ashita フォルダと Vanacore フォルダが並んでいる場所**に置く
3. `適用.bat` を実行する

行うことは次のとおりです。

- `Vanacore\vanacore.ini` に `ashita.interface=4.30` を書く
- その人の Ashita の `imgui.ini` から、FancyChat のウィンドウ位置を VanaCore 側へ写す
- FancyChat と XIUI の VanaCore 向けファイルを、Ashita と VanaCore の両方のアドオンフォルダへ入れる
- PC に Meiryo があり VanaCore 側に無いときだけ、`resources\fonts\meiryo.ttc` へコピーする
- 戦闘ログの魔法アイコン用 `gameicons.ttf` を、VanaCore が読む場所へコピーする

変える前のファイルは、そのフォルダの `backup` に残ります。終わったら VanaCore を起動し直してください。チャット本文はこれまでどおり GDI です。日本語 Windows では、フォント名 `Meiryo` で文字が作れないとき、同じ書体の `メイリオ` で描きます。この bat が足すのは ImGui（設定・タブ、および XIUI）です。

ウィンドウ位置を固定し、「FFXIのUIと重ならないようにずらす」をオンにしているとき、左下の NPC 選択メニューがチャットに被ると、下にある方の窓を横へずらします。VanaCore は `vanacore.ini` の `menu.rows`（3〜12。ゲーム本来は 3）で、そのメニューの行数を変えられます。設定の「選択メニューの行数」を同じ数にしてください。3 のときはこれまでと同じ判定です。

---

## 設定画面が `?` のとき

チャット本文が出ていても、設定・タブは別です。CatsEye の ImGui は当初から日本語です。タブが `?` なのは「1.1.6 より前は日本語化されていなかった」という意味ではありません。VanaCore 向けの登録が CatsEye で通らなかったときや、Windows のフォントをアドオンから開けないときに起きます。1.1.6 は boot のフォント設定を使わず、Windows の Meiryo などを直接読みます。

**やらないこと**

- `boot.ini` / `Ashita/config/boot/catseyexi.ini` に `[ashita.imgui.fonts]` を足さない（CatsEye では次の起動で消えます）
- `"ResetIniFiles"` を `false` にしない
- ゲームフォルダ側の `resources` に `fonts` を作らない（見る場所は **Ashita** フォルダ）
- Windows の言語設定はいじらない
- `/addon reload` だけで済ませない（ImGui のフォントはクライアントの再起動が必要）

`Loaded Font: meiryo.ttc, 18px - is_jp: 1` は Ashita 本体が boot から読んだときの行です。1.1.6 では出なくて構いません。

1. FFXI を完全に終了する
2. 読み込み行が **`fancychat version: 1.1.6 - by: Hando`** であることを確認する。違うならインストールからやり直す
3. ゲームを起動し直し、設定を開く
4. Ashita のログで次を探す

| ログ | 意味と次の手 |
| --- | --- |
| `FancyChat: added ImGui font ...` と `FancyChat: ImGui atlas rebuilt` | 1.1.6 の読み込みは通っている。タブが日本語になる |
| `FancyChat: Japanese glyphs available on the default ImGui font` | すでに別の日本語化が入っている。そのままでよい |
| `FancyChat: could not add a CJK ImGui font this session` | CatsEye が、当時のフォント登録を受け付けていない。フォルダごと **1.1.6** に入れ替える |
| `FancyChat: no CJK font file found. Ashita=...` | Windows のフォントをアドオンから開けていない。下のコピーだけ行う |
| `FancyChat: ImGui font file found but not accepted` | ファイルはあるが登録に失敗。その1行を残す |

`no CJK font file found` のときだけ、次を一度行います。`fonts` フォルダが最初から無いのは想定どおりです。

1. `C:\Windows\Fonts\meiryo.ttc` をコピーする
2. 置く場所は **`Ashita\resources\fonts\meiryo.ttc`**（CatsEye の例: `C:\Games\CatsEyeXI\Ashita\resources\fonts\meiryo.ttc`）。ゲーム本体の `resources` ではない
3. FFXI を完全に終了してから起動し直す

---

## 注意

- 本家と同様、**Ashita 4.30 およびそれ以前**で動く想定です。今後の本家は 4.30 専用になる可能性があります
- ImGui のフォントは `/addon reload` では足りません。タブが `?` のときは FFXI を完全に終了してから起動し直してください
- 超ワイド / 超縦長では **設定 → チャットウィンドウ → 位置オフセット** で位置を調整してください
- `simplelog` など、チャットを書き換える他アドオンとの併用は非対応です。競合したら片方をアンロードしてください
- 同梱の `gdifonts/gdifonttexture.dll` は Thorny 氏の [gdifonts](https://github.com/ThornyFFXI/gdifonttexture) を FancyChat 向けに改変したビルドです。他アドオン用に流用しないでください。改変ソースは本家の [`custom gdifonts src/`](https://github.com/ariel-logos/Fancychat/tree/main/custom%20gdifonts%20src) にあります

---

## コマンド

`/fancychat` と `/fchat` は同じです。マクロにも置けます。

| コマンド | 内容 |
| --- | --- |
| `/addon load fancychat` | 読み込み |
| `/addon unload fancychat` | 終了 |
| `/fchat` | ベースコマンド |
| `/fchat settings` | 設定 |
| `/fchat manual` | ゲーム内マニュアル |
| `/fchat notes` | メモ帳 |
| `/fchat guideme` | Wiki ビューア |
| `/fchat bigmode` | BigMode のオン / オフ |
| `/fchat savelogs` | 全タブをファイルに保存 |
| `/fchat compact` | タブをコンパクト表示に切替 |
| `/fchat tod` | 撃破行に正確な TOD を付ける |
| `/fchat ts` | 現在時刻をチャットに出す |
| `/fchat cjkratio [1.50-2.00]` | 日本語折り返し比率（JP） |
| `/fchat ffo <検索語>` | 用語辞典を検索し、結果を GuideMe に表示 |
| `/fchat translate` | チャット翻訳のオン / オフ |

---

## マウス操作

チャット板の上で:

- **左クリック** — その行（続き行含む）をクリップボードへ
- **Shift + 左クリック** — メモ帳へ（最大 10 件）
- **Ctrl + 左クリック**（ゾーン名がある行） — `/sea`、用語辞典、FFXIclopedia、bg-wiki、マップ
- **`[link]` をクリック** — ブラウザで URL を開く
- **ホイール** — 1 行スクロール。Shift+ホイールは Extra の高速スクロールがオンのとき
- **右クリック** — 最新行へ戻る
- **暗い板をドラッグ** — ウィンドウ移動（位置ロック可）

---

## ゲームパッド

**設定 → ゲームパッド** で「ゲームパッドでチャット操作」をオンにします。**修飾ボタンを押している間だけ** FancyChat の操作になり、離すと通常のゲーム操作に戻ります。

Xbox パッドでの初期割り当て（本家と同じ）:

| 操作 | 初期ボタン | 条件 |
| --- | --- | --- |
| ナビ開始 | 修飾（LB）を押し続ける | 常時 |
| ウィンドウ1のタブ送り | RB | 入力欄が閉じている |
| ウィンドウ2のタブ送り | RT | 第2ウィンドウあり、入力欄が閉じている |
| ウィンドウ1 / BigMode スクロール | 左スティック上下 | 修飾中 |
| ウィンドウ2スクロール | 右スティック上下 | 修飾中 |
| 全ウィンドウを最新へ | B | 修飾中 |
| BigMode | Y | 修飾中 |
| チャット入力を開く | X | 入力欄が閉じている |
| 送信 | A | 入力欄が開いている |
| 入力履歴 | 十字 上 / 下 | 入力欄が開いている |
| プリセット（`!mog` など） | 十字 左 / 右 | 入力欄が開いている |
| BigMode で履歴スクロール | 十字 上 / 下 | BigMode 中、入力欄が閉じている（JP） |
| BigMode でウィンドウ1 / 2 | 十字 左 / 右 | BigMode 中、第2ウィンドウあり、入力欄が閉じている（JP） |

DirectInput では初期の Xbox 番号と物理ボタンが一致しません。設定画面の「最後に受けた入力」を見ながら、修飾や BigMode などを取り直してください。十字キーはハットとして自動認識するので、左右をボタン番号に割り当てる必要はありません。

---

## 設定パネル

`/fchat settings` で開きます。

1. **チャットウィンドウ** — 幅、行数、第2ウィンドウ、位置、自動非表示、「FFXIのUIと重ならないようにずらす」、選択メニューの行数、ゲームパッド など
2. **フォント色** — チャンネル色と、入手・経験値・自分 / 敵名など。日本語ログの文言色はコンパクト戦闘ログと FC color marking がオンのときが本筋です
3. **ショートカット** — 非表示 / BigMode / タブ送り（初期はオフ）
4. **その他** — 旧チャット遮断、戦闘フィルタ、コンパクト戦闘、タイムスタンプ、通知音 など
5. **CL フィルタ** — `combatfilters/*.txt`
6. **翻訳** — ASCII チャットの日本語化、サイトと API キー、辞書
7. **ツール** — ログ保存、マニュアル、旧チャット復元
8. **クレジット** — オリジナル版と JP 版のバージョン・作者

---

## ファイルの場所

- **キャラごとの設定** — `Ashita/config/addons/fancychat/<キャラ名>/settings.json`
- **色セット** — `addons/fancychat/chatcolors/`
- **戦闘フィルタ** — `addons/fancychat/combatfilters/*.txt`
- **保存ログ** — `Ashita/config/addons/fancychat/logs/<キャラ名>/ChatLogs_<日時>/`
- **翻訳辞書** — `Ashita/config/addons/fancychat/translate/dict.txt`
- **通知音** — `addons/fancychat/notifications/*.wav`
- **マップ** — `addons/fancychat/maps/<ゾーン>/<分類>/`
- **ImGui 用フォント（通常は不要）** — Windows のフォントを読めないときだけ `Ashita/resources/fonts/meiryo.ttc`。アドオンには同梱しません

ログはアンロード時に自動保存されません。`/fchat savelogs` か設定のツールから保存してください。

---

## 開発者向け（このフォーク）

Lua ソースに日本語を直書きすると、Shift-JIS な環境で壊れます。GUI 文言は十進エスケープ（`\227\129\147` など）にするか、`_escape_lua_utf8.py` で変換してください。`utils.lua` 全体にはスクリプトをかけないでください（FFXI マップやアイコンが壊れます）。内部のタブ名や ImGui の `##` ID は英語のままです。

---

## 免責・AI

本家 README と同様、ドキュメントとリファクタの一部は AI 支援で書いています。設計・ゲーム内確認・このフォークでの判断は作者の責任です。

---

## クレジット

- **Arielfy** — [FancyChat](https://github.com/ariel-logos/Fancychat)（オリジナル `1.0.260721R`）
- **Hando** — FancyChatJP `1.1.6`
- **[Ashita](https://www.ashitaxi.com/)** — フレームワーク
- **atom0s** — `targets.lua` とエンティティ解決
- **Thorny** — gdifonts
- **[game-icons.net](https://game-icons.net/)** — `gameicons.ttf`

オリジナルの機能・注意の一次情報は必ず [本家 README](https://github.com/ariel-logos/Fancychat) を確認してください。
