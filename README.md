# FancyChat JP

[Arielfy 氏の FancyChat](https://github.com/ariel-logos/Fancychat) の日本語向けフォークです。

Ashita 用のチャット置換アドオンです。FFXI 標準チャットの代わりに、タブ分け・戦闘ログの短縮・色分け・マップ検索などを備えたオーバーレイを出します。このフォークでは、**日本語クライアント**での表示・折り返し・設定画面の日本語化に加え、日本語ログ向けの色判定や DualShock など DirectInput パッドへの対応を足しています。

| | |
| --- | --- |
| オリジナル | [Arielfy / FancyChat](https://github.com/ariel-logos/Fancychat) `1.0.260721R` |
| このフォーク | [handomade / FancyChatJP](https://github.com/handomade/FancyChatJP) |
| 作者 | オリジナル: Arielfy　／　JP: Hando |
| バージョン | オリジナル `1.0.260721R`　／　JP `1.1.1`（FancyChatJP 独自採番） |

動作確認は CatsEyeXI（Ashita）上の日本語クライアントを想定しています。本家の機能はそのまま使えるようにしつつ、JP 向けの差分だけを足しています。バージョンは本家の日付付き番号（例: `1.0.260721R`）に合わせず、このフォークだけで上げます。

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

- チャット本文は GDI（既定 Meiryo）。Shift-JIS → UTF-8 と、全角幅を考慮した折り返し（`cjkWidthRatio`）
- 設定ウィンドウ・タブ名・ツールチップ・マニュアルなどの **ImGui 文言の日本語化**
- 日本語ログでも、入手・経験値・戦闘短縮などの**文言ベースの色**が乗るようパターンを追加（本家は英語メッセージ前提だったため、日本語ではドロップ色などが効かないことがありました）

チャット本文の日本語はアドオンだけで出ます。一方、設定画面などの ImGui は Ashita 既定フォントに日本語が無いと `?` になります。下の「ImGui を日本語にする」を見てください。

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

1. ゲームを終了する
2. `Ashita/addons/fancychat` をフォルダごと削除する
3. [FancyChatJP の Releases](https://github.com/handomade/FancyChatJP/releases) かリポジトリ一式を、`Ashita/addons/fancychat` に置く（ZIP なら中の `fancychat.lua` がこのフォルダの直下にあること。`FancyChatJP-main/fancychat.lua` のまま一段深いと読みません）
4. ゲーム内で:

```
/addon load fancychat
```

正しく入っていれば、読み込み行は **`fancychat version: 1.1.1 - by: Hando`** です。`0.9.xxxxxx - by: Arielfy` のままなら、まだ本家が残っています。

5. ランチャーの **ADDONS** で FancyChat の **Ignore Updates** にチェックを付ける
6. 自動起動するなら、Ashita の default スクリプトの**末尾付近**に `/addon load fancychat` を追加する。ほかのチャット系アドオンより後が安全です

起動後は `/fchat settings` で設定、`/fchat manual` でゲーム内説明です。

### CatsEyeXI の Ignore Updates（必須）

ランチャーは公式アドオンとして本家 FancyChat を配っています。**Ignore Updates が外れていると、アドオン更新のたびに JP の Lua が本家（`0.9` / Arielfy）で上書き**されます。混ざると `ApplyWindowTabBuffer` が無い、といったエラーになります。

1. ランチャーの **ADDONS** タブを開く
2. FancyChat の **Ignore Updates** にチェックを付ける
3. 保存先はランチャーと同じフォルダの `cexi_settings.json` で、`"IgnoreUpdatesAddons"` に `fancychat` が入ります

チェックを付けなくても上書きされないことがあります（フォルダが FancyChatJP の別 git になっている、まだ FancyChat の更新が来ていない、など）。**保証ではない**ので、JP を使うならチェックは付けてください。JP をやめて本家に戻すときだけ外します。

---

## ImGui を日本語にする（任意）

チャット本文の日本語は FancyChatJP だけで出ます。設定画面などの ImGui が `?` になるときだけ、この節を見てください。

**CatsEyeXI では、まず何もしなくて構いません。** アドオンが起動時に Windows の Meiryo / MS Gothic / Yu Gothic を探して ImGui に足します。設定画面が日本語なら、boot ini はいじらないでください。

どうしても Ashita 本体の boot フォントにしたい場合だけ、次です。

1. `meiryo.ttc` を `Ashita/resources/fonts/` に置く（Windows の `C:\Windows\Fonts\meiryo.ttc` をコピー。Meiryo は再配布できないのでリポジトリには入れていません）
2. 起動に使う boot プロファイル（CatsEyeXI なら `Ashita/config/boot/catseyexi.ini`）の**末尾**に次を足す:

```ini
[ashita.imgui.fonts]
font0.family=meiryo.ttc
font0.size=18
font0.is_jp=true
```

3. **FFXI を完全に終了してから**起動し直す（`/addon reload` では足りません）
4. 起動ログに `Loaded Font: meiryo.ttc, 18px - is_jp: 1` と出ていれば成功です

フォントファイルが無いのにこの節を足すと、Ashita が起動に失敗することがあります。そのときは節を消すか、`meiryo.ttc` を置いてください。

### CatsEyeXI ランチャーと boot ini（ResetIniFiles は使わない）

ランチャーはゲームを出すたびに `Ashita/config/boot/catseyexi.ini`（boot プロファイル。`boot.ini` というファイル名ではない）を作り直します。解像度・サーバー接続・入力設定などを、ランチャー側の値で上書きするためです。だから `catseyexi.ini` に書いた `[ashita.imgui.fonts]` は、次の起動で消えることがあります。これは想定どおりの動作です。

`ResetIniFiles` は **boot プロファイルではなく**、ランチャー本体の設定ファイルにあります。

- ファイル名: `cexi_settings.json`
- 場所: CatsEyeXI ランチャーと同じフォルダ（例: `...\catseyexi-launcher\cexi_settings.json`）
- 項目: `"ResetIniFiles": true` が既定。`false` にすると boot プロファイルを作り直さない

**ここを `false` にしないでください。** フォント用に切ると、次のような事故が起きます。

- ランチャーが解像度や接続コマンドを ini に書けなくなる
- 編集で ini が壊れたとき、自動修復されない
- `meiryo.ttc` が無い `[ashita.imgui.fonts]` が残ったままになり、Ashita / ランチャーが起動エラーのまま固まる
- ランチャーを再起動しても、壊れた ini を使い続ける

すでに `false` にして起動できなくなった場合:

1. `cexi_settings.json`（ランチャーと同じフォルダ）の `"ResetIniFiles"` を **`true` に戻す**（またはその項目を消して既定に戻す）
2. ランチャーを起動し、`Ashita/config/boot/catseyexi.ini` が作り直されるのを待つ
3. それでも起動しないときは、`catseyexi.ini` を別の名前に退避してからランチャーを起動する（新しい ini が作られます。ログイン情報はランチャーに入れ直すことがあります）
4. 日本語 UI は FancyChatJP の自動フォント読み込みに任せる

フォントを boot ini に残したい場合でも、**ResetIniFiles は true のまま**、ゲームを出したあと毎回 `[ashita.imgui.fonts]` を足すか、アドオン側の自動読み込みを使ってください。

---

## 注意

- 本家と同様、**Ashita 4.30 およびそれ以前**で動く想定です。今後の本家は 4.30 専用になる可能性があります
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

1. **チャットウィンドウ** — 幅、行数、第2ウィンドウ、位置、自動非表示、ゲームパッド など
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
- **Hando** — FancyChatJP `1.1.1`
- **[Ashita](https://www.ashitaxi.com/)** — フレームワーク
- **atom0s** — `targets.lua` とエンティティ解決
- **Thorny** — gdifonts
- **[game-icons.net](https://game-icons.net/)** — `gameicons.ttf`

オリジナルの機能・注意の一次情報は必ず [本家 README](https://github.com/ariel-logos/Fancychat) を確認してください。
