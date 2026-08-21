# ADR-0035: 並列 Worktree の資源統治（公式ライフサイクル前提・ccs は Resource Governor + Quality Layer）

## ステータス

**承認済み（2026-08-21）**。MVP 未実装。前提は ADR-0018（目的と最小ループ）・ADR-0015（下流の ccs 不意識運用）・ADR-0023（文脈経済）・ADR-0027（公式スキル採用とラップ配布）・ADR-0032（enforcement は fail-closed）。

**採番について**: 本 ADR は `0035` を取得する前提で書かれている。`origin/main` に `0035` は未使用だが、**並行するブランチにも `0035` を名乗る ADR が存在する**。本ブランチを先にマージする場合、他の `0035` はマージ前に再採番が必要になる。**push / PR の前に `origin/main` と他の PR を再確認する**（本ファイルは現時点で再採番しない）。

## 背景

並列 Worktree（以下 WT）運用が実用規模に達し、次の 4 つが同時に起きている。

1. **掃除器が O(N)**: 下流の実装事例では、1 件だけを対象にした操作でも全 WT を走査する。55 本規模で 1 件の対象指定操作に約 7 分、full 回帰は実スクリプトを約 22 回起動して約 31 分かかる。**対象 1 件の操作コストが、無関係な WT の本数に比例している。**
2. **圧迫しているのは node_modules ではない**: ディスクよりも、Claude / tsserver / dev server / Vitest / Playwright / watcher の**常駐プロセス**が PC を圧迫している。node_modules の重複は容量の問題であって、同時実行数の問題ではない。
3. **共有 node_modules は事故を起こした**: junction 共有した node_modules を残したまま WT を撤去し、リンクを辿ってメインワークスペースの実体が削除された（2026-07-23・v0.18.0 の Guard 5.5 はこの事故への強制層）。
4. **WT のライフサイクルは公式ハーネスの機能になった**: WT の作成・通常削除・subagent の隔離実行・gitignored ファイルの持ち込みが公式側で扱える。ここで ccs が独自の WT manager を作ると、**同じ対象を二重に管理する**ことになり、公式側の変更に追随し続けるコストを下流全体が負う。

ADR-0027 は「公式が持つ機構は公式に委ね、ccs は OS 層と指揮者に縮約する」と定めている。WT ライフサイクルはその適用対象である。

## 位置づけ — ccs は WT manager を作らない

ccs が持つのは、公式が扱わない 2 つの層に限る。

| 層 | ccs の責務 | 理由 |
|---|---|---|
| **Resource Governor** | マシン内の同時実行数の統治（heavy / runtime の枠） | 公式は WT のライフサイクルを扱うが、**マシン全体の資源競合**は扱わない。ここが実際に PC を圧迫している（背景 2） |
| **Quality Layer** | 資源に関わる判断の質（判定の決定的化・fail-closed・回帰） | ccs の既存の価値（決定的検査・判定不能を許可へ合流させない）をそのまま適用できる面 |

WT の作成・削除・隔離・配布は**公式へ委譲する**。

## 前提とする公式機能 — Claude Code 2.1.238 での characterization 結果

下記は **Claude Code 2.1.238** を対象に scratch 環境で一次確認した観測結果である。**特定バージョンでの観測であり、普遍的な仕様として扱わない**（再確認の規定は「既知の限界」7）。

| 前提 | 観測結果（CLI 2.1.238） | 確認方法 | 観測範囲 |
|---|---|---|---|
| `isolation: "worktree"` | **確認済み**。WT は `<repo>/.claude/worktrees/agent-<hash>` に作られ、**新規ブランチ `worktree-agent-<hash>`** をチェックアウトする。**正常終了時は WT・登録・ブランチのすべてが自動削除**され、**`SIGKILL` では 3 つとも残り、`git worktree list` に `locked` として登録が残る** | scratch リポジトリで subagent を実走し、前後の `git worktree list` / `branch` / ディレクトリを観測 | 実行中の WT も `locked` として現れる（`locked` は実行中と孤児を区別しない） |
| `.worktreeinclude` | **確認済み（現行環境に存在）**。gitignored ファイルを `git ls-files --others --ignored --exclude-standard --directory` で解決し、WT へ**コピー**する。symlink はスキップし、コミット済み symlink 経由で WT 外へ出る宛先は拒否する | 実体の文字列（該当機能のメッセージ群）+ scratch で isolation WT へのコピーを実走確認 | subagent の isolation WT で有効であることを確認。通常 WT での挙動は未観測 |
| `WorktreeRemove` hook | **確認済み（正式なイベント）**。payload は共通フィールド + `worktree_path` | 実体のイベント名 enum と schema、および実走 | **subagent の isolation WT が自動削除される経路では発火しなかった**。`SIGKILL` でも発火しない |
| `SessionEnd` hook | **確認済み（正式なイベント）**。payload は共通フィールド + `reason`（`clear` / `resume` / `logout` / `prompt_input_exit` / `other`） | 実体の schema + 非対話実行での実発火 | 非対話の正常終了では `reason: other` で発火。**`SIGKILL` では発火しない** |
| `claude agents` | **確認済み**。`--json` は **TTY 不要**で `cwd` / `kind` / `name` / `pid` / `sessionId` / `startedAt` / `status` を返す。`--cwd <path>` で絞り込める | `--help` とサブコマンド一覧、および実走 | **セッション単位**の一覧であり、**in-process の subagent は列挙されない** |
| `WorktreeCreate` hook | **確認済み。ただし観測用ではない**（決定 5） | 実体の schema（`hookSpecificOutput.worktreePath`）+ 実走で起動失敗を再現 | **WT パスを返す provider hook**。配線して空出力だと `isolation: "worktree"` の起動自体が失敗する |

**観測の生データは追跡ツリーに置かない**（ADR-0030）。本 ADR に残すのは**観測結果・対象 CLI 版・そこから導いた判定・制約**だけである。

## 決定

### 決定 1: 役割分界 — 公式に委譲するものと ccs が持つもの

| 対象 | 担当 | ccs の関与 |
|---|---|---|
| WT の作成 | **公式** | なし |
| WT の通常削除 | **公式** | なし。**公式管理の WT を削除する独自 CLI を持たない** |
| subagent の隔離実行 | **公式**（`isolation: "worktree"`） | なし |
| gitignored ファイルの持ち込み | **公式**（`.worktreeinclude`） | なし。**コピー**であり symlink は拒否される（決定 8） |
| node_modules の用意 | **利用者 / package manager** | なし。共有リンク禁止の規範だけ残す（決定 8） |
| **同時実行数の枠** | **ccs** | 本 ADR の中核 |
| **枠の判定の決定的化・fail-closed** | **ccs** | 本 ADR の中核 |
| 例外的な WT の診断 | **ccs**（doctor・報告のみ） | 決定 7 の閉集合に限定 |

**ccs は WT を削除しない。** 破壊操作を持たないことで、破壊前条件・ホワイトリスト・破壊直前の再検証・`--force` 禁止といった一連の機構が**そもそも不要になる**。安全性を機構で担保するのではなく、危険な操作を持たないことで担保する。

### 決定 2: 資源枠は executionDomain 単位・上限は利用者管理の設定が既定

- **枠は 2 種類**: `heavy`（既定 **1**。test / typecheck / build / Playwright / pre-push）と `runtime`（既定 **2**。dev server / watcher / tsserver）。
- **スコープは executionDomain 単位**。store は **domain-local** で、リポジトリにも WT にも紐づけない — 同一 domain 上の全プロジェクト・全 WT が 1 つの枠を共有する。**domain をまたぐ共有はしない**（`os.tmpdir()` も `~` も Windows / WSL で別実体であることを実測済み。`$HOME` = `/home/<user>` と `C:\Users\<user>` は別ディレクトリ）。
- **上限の既定は domain-local の設定ファイル `resource-policy.json`**（**利用者が管理する**）。リポジトリの clone / checkout / 取り込みで書き換わらないための置き場所であり、**agent が書けない security boundary ではない**（shell を持つ agent は同じユーザー権限で到達できる）。守っているのは*事故と drift*であって*敵対的改変*ではない。
- **リポジトリ内の設定・環境変数は上限を引き上げられない。** 合成は `min(policy, repo, env)` の一方向で、repo / env は**下げることしかできない**。defense-in-depth であり、改変不能性の主張ではない。
- **「未設定」と「壊れている」を区別する**（never-configured と configured-then-drifted を混同した ADR-0032 と同型の失敗を避ける）。

  | policy の状態 | effective default | 理由 |
  |---|---|---|
  | **不在**（ファイルが無い） | `heavy=1, runtime=2`（組み込み既定） | 未設定は正常な初期状態。大多数の利用者はこのファイルを作らない。ここを 1 に倒すと通常運用が常時縮退する |
  | **読めない / JSON 不正 / 非数値 / 0 以下 / 型不一致** | **`heavy=1, runtime=1`** | 「設定を読めなかった」を「上限なし」にも「組み込み既定」にも合流させない |

  組み込み既定（1 / 2）は**未実測の初期値**であり、実測で調整する対象である。

### 決定 3: slot は固定 cell の atomic 取得で守る

- **一意 token を `O_EXCL` で作ってから占有数を数える方式は上限を守れない** — 2 プロセスが同時に「現在 N-1 本」と数え、両方が作成に成功して N+1 本になる。**数えてから作る限りこの窓は消せない。**
- 上限 `N` から **固定 cell `slot-0` 〜 `slot-(N-1)`** を導出する。
- **index `i` の占有判定は `slot-<i>.json` の存在だけでは足りない。** `slot-<i>.json` **または** `quarantine-slot-<i>-<unique>` の**いずれかが存在すれば、その index は占有中**とする。回収の途中（quarantine 中）の index を空きと見なすと、**回収対象が ACTIVE と判明して戻すときに戻し先が埋まっている**という状態が生まれ、その瞬間 index `i` に 2 本が同時に存在する。
- 取得の手順（index `i` について）:
  1. `quarantine-slot-<i>-*` が存在すれば **`i` を飛ばす**（回収中の index は取らない）。
  2. `slot-<i>.json` を **`O_EXCL` で作成**する。`EEXIST` なら `i` を飛ばす。**作成の成否そのものが排他**であり、別途の計数を判定に使わない。
  3. **作成に成功したら quarantine を再確認する。** 手順 1 と 2 の間に他プロセスが `slot-<i>` を quarantine へ rename していた場合、この時点で quarantine と自分の新 cell が同じ index に併存する。**その場合は自分が作った cell を削除して `i` を飛ばす**（自分が後から入った側なので自分が退く）。この再確認が無いと手順 1〜2 の窓が残る。
- 全 index が占有（cell または quarantine）なら `RESOURCE_BUSY`。待つかどうかは呼び出し側が決める（既定はポーリング待ち・**取得待ちタイムアウトつき**。命名は決定 5 を参照）。
- **上限を下げた直後は、既に取得済みの cell が解放されるまで実効同時数が新上限を上回りうる**（縮退は解放時に効く）。
- **通常の解放は自分の cell だけ**: cell 内の owner token を照合してから削除する。**他 owner の cell を消す経路をコードに持たない。** 解放は冪等で、正常終了・異常終了・シグナルのいずれでも同じ経路（`finally`）を通る。
- **stale 回収は quarantine への atomic rename を先に行う**（「検証してから消す」順序だと、2 プロセスが同じ cell を STALE と判定して両方が回収し、両方が取り直して上限を超える）。
  1. cell を**一意の quarantine 名**（`quarantine-slot-<i>-<unique>`）へ `rename` する。rename は atomic なので、**成功した 1 プロセスだけが回収者**になる。**この時点でも index `i` は占有中のまま**である（取得側が quarantine を占有として扱うため）。
  2. **rename 後に、quarantine 側の内容で再検証する**（決定 4 の真理値表）。rename 前の判定を根拠にしない — 判定と rename の間に状態が動きうるため、**確定は必ず rename 後の再検証で行う**。
  3. **STALE と確定したときだけ削除**する。削除して初めて index `i` が空く。
  4. **ACTIVE / ACTIVE_EXPIRED / INDETERMINATE と判明したら、元の cell 名へ rename して戻す**（誤回収の巻き戻し）。取得側が quarantine 中の index を取らないため、**戻し先が埋まっていることはない**。
  - **取得直後で内容がまだ書かれていない cell を stale と誤認しない**ため、作成からの猶予（grace）を経過した cell だけを回収対象にする。
- **MVP が持つ timeout は `acquireTimeoutMs`（slot の取得待ち）だけ**とする。超過時は cell を取らずに `RESOURCE_BUSY` で戻る（副作用なし）。
- **取得後のコマンド寿命に timeout を持たない。** ラップした実コマンドの寿命は**呼び出し元・CI・既存の timeout 機構へ委譲**する。`with-slot` は**子の終了を待ち、`finally` で slot を返す**だけである。
  - 理由: コマンドの timeout を実装すると、Windows を含む process tree の終了・シグナル転送・孤児プロセスの回収まで必要になり、Resource Governor の MVP が大きく膨らむ。さらに「**プロセスの自動 kill は作らない**」（非目標）と正面から矛盾する。
  - **command timeout の統合は Phase 4 以降の別判断**とする。名前を先に決めるなら `commandTimeoutMs` だが、**MVP では実装しない**。

- **再入（reentrancy）の契約**: heavy コマンドが内部で別の heavy コマンドを呼ぶとき、自己デッドロックを避けるため内側は素通しする。ただし**素通しの条件を boolean マーカーにしない** — 「保持中」を表す真偽値だけだと、**古い環境変数の残骸や利用者の手動設定でも素通しが成立し、slot を消費しないまま重い処理が走る**。

  | 役割 | 契約 |
  |---|---|
  | **外側の `with-slot`** | **唯一の slot owner**。取得・解放の責任を持つ |
  | **子プロセスへの引き渡し** | `kind` / `index` / **秘密 token** を環境変数で渡す（owner の process tree にのみ継承される） |
  | **内側の `with-slot`** | 受け取った `kind` / `index` で cell を読み、**秘密 token が cell の `releaseTokenHash` と照合できたときだけ**再入として素通しする |
  | **内側は解放しない** | 解放するのは外側だけ。内側が `finally` で解放すると、外側がまだ使っている枠が返る |
  | **照合できない場合** | 素通ししない。**通常の取得を試みる**（token 不一致・cell 不在・`kind`/`index` の欠落・JSON 破損のいずれも）。取得できなければ `RESOURCE_BUSY`。**判定不能を素通しへ倒さない（fail-closed）** |

  この環境変数は「**N 本のうち 1 本を保持している**」という意味であり、**排他の証明ではない**。子プロセスの並列度をこの値から決めると、複数本が同時に走ったときにコア数を超える。並列度を決めるなら取得時点の占有数を別のキーで渡す。

### 決定 4: slot cell の真理値表（ownership lease は持たない）

**session ownership の lease を廃止する。** 「この WT は誰の作業か」は公式の WT ライフサイクルとセッションが持つ情報であり、ccs が別に台帳を持つと写し書きになる（ADR-0031）。ccs が持つのは **slot cell だけ**で、その付帯情報として占有者を記録する。

```json
{
  "v": 1,
  "kind": "heavy | runtime",
  "owner": "<session id>",
  "executionDomain": "wsl:<distro>:<uid> | win:<user>",
  "pid": 12345,
  "label": "<診断用の短い文字列>",
  "releaseTokenHash": "<秘密 token のハッシュ。通常解放の権限はこれとの一致で決まる>",
  "worktreeKey": "<診断・検索用。解放権限ではない>",
  "createdAt": "2026-08-21T02:00:00Z",
  "leaseUntil": "2026-08-21T10:00:00Z"
}
```

**保存しない**: 作業内容・経緯・PR 状態・head SHA・ブランチ名・WT の状態。これらは公式・git・GitHub から derive する。

| # | `leaseUntil` | PID | domain | 判定 | 回収 |
|---|---|---|---|---|---|
| 1 | 未来 | 生存 | 同一 | **ACTIVE** | 不可 |
| 2 | 未来 | **死亡** | 同一 | **STALE** | 可（grace 経過後） |
| 3 | **過去** | **生存** | 同一 | **ACTIVE_EXPIRED** | **不可** |
| 4 | 過去 | 死亡 | 同一 | **STALE** | 可 |
| 5 | 任意 | 判定不能 | **foreign domain の cell が現れた** | **INDETERMINATE** | 不可 |
| 6 | 解析不能（JSON 破損・必須欠落） | — | — | **INDETERMINATE** | 不可 |

- **#3「期限切れ + PID 生存」は回収しない。** プロセスが生きている以上、実際に重い処理が走っている可能性が高い。回収すると**二重割り当て**になり、期限更新漏れというバグを資源枯渇に変換する。doctor が可視化し、対処は人間に残す。
- **#2「期限内 + PID 死亡」は回収する。** 保持者がクラッシュした状態であり、待ち続けても解放されない。ただし作成直後の grace 内は回収しない。
- 判定は常に **cell 自身の属性**だけで行い、**待ち手の経過時間を材料にしない**（長く待った waiter が取得直後の生きた cell を stale と誤認して壊すため）。
- store は domain-local なので通常運用で #5 は出現しない。WT を domain 間で移動した場合や `executionDomain` を解決できない場合の防衛として残し、出現したら停止側へ倒す。

### 決定 5: 公式との接続点は「観測と stale 再検証の trigger」だけ

`WorktreeRemove` / `SessionEnd` に配線するのは**観測と再検証の trigger のみ**とする。**配線自体は MVP に含めない（Phase 4 以降）** — MVP は hook 無しで成立する枠を先に作り、hook はその後に足す。

**`WorktreeCreate` は配線しない（禁止）。** これは観測 hook ではなく、**作成する WT のパスを返す provider hook** である。配線して何も返さないと `isolation: "worktree"` の起動そのものが失敗する（実走で再現）。ccs が独自の WT provider を実装すると決定しない限り、この hook には触れない。

- **やること**: **観測記録**と、**該当 index の再検証（stale recovery）の trigger**。
- **やらないこと**: **WT の削除**（公式の責務）、**許可・拒否の判定**（hook の戻り値で公式の操作を止めない）、破壊的な後始末、そして**ACTIVE な cell の解放**。
- **hook は cell を「解放」しない。** できるのは決定 3 の stale recovery を早めに起動することだけで、**実際に消えるのは PID 死亡かつ再検証で STALE と確定した cell のみ**である。`ACTIVE` / `ACTIVE_EXPIRED` / `INDETERMINATE` は hook 経由でも解放されない。
- **解放権限は秘密 token に紐づく。** 通常解放は `with-slot` が取得時に生成して**プロセス内に保持する秘密 token**が cell の記録と一致したときだけ成立する。**session ID と worktree key は診断・検索用のキーであって解放権限ではない** — これらで解放できる設計にすると、同じ session ID を持つ別プロセスや、WT を共有する別セッションが、生きている cell を解放できてしまう。
- **解放経路の対応表**:

  | 終了のしかた | 解放経路 |
  |---|---|
  | 正常終了 | `with-slot` の `finally`（秘密 token 一致） |
  | 捕捉可能なシグナル（`SIGINT` / `SIGTERM` 等） | 同上（ハンドラから `finally` へ合流させる） |
  | `SIGKILL` | **stale recovery のみ**。`finally` が走らず **`SessionEnd` も `WorktreeRemove` も発火しない**ことを CLI 2.1.238 で**実測済み**。回収の根拠は **PID 死亡**だけである |
  | プロセスクラッシュ / 電源断 | **stale recovery のみ**。`finally` や hook の完走を正しさの根拠にできないため回収経路を stale recovery に限定する（**SIGKILL 以外を実測済みとは主張しない**） |
  | 公式 hook（`WorktreeRemove` / `SessionEnd`） | **解放しない。** stale recovery を早く起動するだけ（`WorktreeRemove` は発火しない経路がある） |

- **これらの hook は advisory 扱い**とする（ADR-0032 の分類）。起動に失敗しても公式の操作を妨げない。取りこぼした cell は決定 3 の stale 回収が拾う — **hook は最適化であって、正しさの根拠ではない。**
- **`WorktreeRemove` は全経路では発火しない。** subagent の isolation WT が自動削除される経路では発火しないことを実測した（CLI 2.1.238）。したがって **slot の正しさ・通常解放・回収の根拠にしてはならない**。用途は「発火する一部経路での advisory な再検証 trigger」に限定する。
- **前提が崩れた場合の縮退**: hook が利用できない場合でも、`with-slot` の `finally` と stale 回収だけで枠は成立する。hook はクラッシュ時の回収を早めるだけである。

### 決定 6: Cold / Ready / Running を制御の中心に置かない

WT の状態（node_modules の有無・常駐プロセスの有無）は**診断語彙として残すが、制御の入力にしない**。

- 枠の判定は **slot cell だけ**を見る。WT の状態を見て枠を決めない。
- 「軽量 WT / 通常 WT」という恒久的な種類も持たない（種類は作成時の一度きりの判断で、実体とずれる）。
- WT の状態は doctor の報告に現れるだけで、取得・解放・回収のどの分岐にも入らない。**制御パスから状態推定を排除する**ことで、判定を cell の属性だけで閉じる。

### 決定 7: legacy doctor は閉集合・報告のみ・hot path に配線しない

公式のライフサイクルに乗らない対象だけを診断する。**閉集合で定義し、それ以外を対象にしない。**

1. 非対話実行（`-p`）で作られ、公式の撤去経路を通らなかった WT
2. 利用者が手で作った WT
3. 異常終了で取り残された WT / slot cell
4. 本モデル導入前の方式で作られた WT

- **doctor は MVP に含めない（Phase 4 以降）。** MVP は Resource Governor（決定 2・3・4）だけを作る。本決定は doctor を作るときの制約を先に固定するものである。
- **doctor は報告のみ**。削除しない。提案は出すが、実行するのは利用者か公式の経路である。

#### doctor の分類 — 一覧の不在を孤児の証拠にしない

`claude agents --json` は**セッション単位**の一覧で、**in-process の subagent は列挙されない**。また **active な isolation WT も `git worktree list` では `locked` として現れる**（実行中と孤児を `locked` では区別できない）。したがって「`locked` かつ一覧に PID が無い」だけで孤児と断定すると、**実行中の subagent WT を孤児と誤判定する**。

| 分類 | 条件 | doctor の動作 |
|---|---|---|
| **ACTIVE_CONFIRMED** | `claude agents --json` に一致するセッションがある | 触れない（報告に「稼働中」と出す） |
| **ORPHAN_CANDIDATE** | 一致が無く、かつ age・`locked` 状態などから孤児の可能性がある | **候補として報告するだけ**。削除も自動確定もしない |
| **INDETERMINATE** | 一覧を取得できない・解析できない・判定材料が欠ける | **判定不能として報告**。ORPHAN 側へ倒さない |

- **一覧に無いことを STALE や孤児の確定根拠にしない。** 不在は「観測できなかった」であって「存在しない」ではない。
- 報告には **age・`git worktree` の `locked` 状態・関連セッションの有無**を併記するが、**それらの組み合わせで自動確定しない**。
- **doctor は報告のみで削除しない**（決定 1）。処遇の判断は利用者と公式の経路に残る。

- **pre-commit / pre-push に配線しない。** O(N) の走査を commit / push の hot path に置くと、WT 本数の増加がそのまま日常操作の遅延になる（背景 1 の再生産）。呼び出しは `/weekly-inventory` または夜間に限る。
- **監視 UI は `claude agents --json` を第一候補**とする。**TTY 不要**で `pid` / `cwd` / `status` を取得でき、`--cwd` で絞り込める。ただし**in-process の subagent を含む完全な実行一覧ではない** — **正の存在確認には使えるが、不在証明には使わない**（決定 7 の分類）。**doctor のテキスト出力による縮退経路は残す**（一覧を取得できない環境でも報告が成立するようにする）。

### 決定 8: 共有 node_modules は禁止のまま・store の共有は可

- **node_modules の junction / symlink 共有を禁止する**（規範として維持）。Guard 5.5 は強制層として残す。
- **package manager の共有 store（pnpm store / npm cache 等）は利用してよい。** store から WT 内へ張られるリンクは「WT 内の実体」であり、WT を消しても store は壊れない。禁止するのは **WT 間で node_modules ディレクトリそのものを共有する**形だけである。
- **`.worktreeinclude` は該当ファイルを WT へ「コピー」し、symlink はスキップする**（コミット済み symlink 経由で WT 外へ出る宛先も拒否される）。したがって **`.worktreeinclude` がコピーしたファイルについては**、リンクを辿って共有元を壊す事故クラスが構造的に生じない。**この保証はコピーされたファイルに限る** — `.worktreeinclude` は node_modules の用意には関与しないため、**共有 node_modules に起因する事故まで防ぐわけではない**。共有リンク禁止の規範は維持する。
- node_modules の作成・削除そのものに ccs は関与しない（決定 1）。

### 決定 9: プロジェクト固有の規則は adapter 境界に置き、MVP では実装しない

`release/stg` / `feature/*` のブランチ規則、migration 直列の占有宣言、作業台帳との連携といったプロジェクト固有の要求は、公式設定だけでは満たせない。これらは **project adapter 境界の外側**に置く。

- ccs コア（policy / domain / slots / with-slot）は**ブランチ名もプロジェクト構成も知らない**。
- adapter は下流プロジェクトが実装する。**MVP では adapter を実装しない**（境界を宣言するだけ）。
- コアに 1 つでもプロジェクト固有の分岐を入れると、以後すべての下流がその分岐を引き受ける。

### 決定 10: テストは純粋 fixture 中心・実プロセスは最小

- **判定（真理値表・policy 合成）は純粋関数**とし、JSON fixture で網羅する（実プロセスを起動しない・ミリ秒で回る）。
- **並行性の受入条件だけは実プロセスで確認する**（純粋関数では競合を再現できないため）。次の 5 点に限定し、**Phase 3（MVP）は 1〜4、回帰 5 は hook 配線と同じ Phase 4** とする（回帰 5 は hook が無ければ発火させられないため、MVP の受入条件に含めない）。

  | # | Phase | 回帰 | 何を守るか |
  |---|---|---|---|
  | 1 | **3** | 上限 `N` に対し `N + k` 本を同時起動し、成功数が**正確に `N`** | 固定 cell 方式の中核。count→create 方式ならここで超過が観測される |
  | 2 | **3** | **`N = 1` で回収と取得を競合させ、同時実行数が 1 を超えない** | **quarantine 中の index を空きと見なす実装だとここで 2 本走る**（決定 3） |
  | 3 | **3** | 同一 stale cell に複数プロセスが同時に回収を試みても、rename 成功は 1 つだけ | 二重回収による超過 |
  | 4 | **3** | `SIGKILL` 後に stale recovery で枠が戻る | `finally` が走らない経路の回収 |
  | 5 | **4** | **`SessionEnd` 相当の trigger 時に子プロセスが生存していれば cell が残る** | **hook が ACTIVE を解放しないこと**（決定 5）。解放されたらここで落ちる |

  2 と 5 は本改訂で追加した回帰であり、**それぞれ決定 3・決定 5 の load-bearing な性質を直接指す**。回帰 5 は hook 配線（Phase 4）と同時に入れる。
- **テスト時間が実リポジトリの WT 数・プロセス数に比例しない**こと。
- **fault injection は load-bearing 箇所だけ**: 上限の厳守、policy 破損時の縮退、INDETERMINATE が回収へ倒れないこと、**quarantine を占有として数えない実装に差し替えたら回帰 2 が落ちること**（Phase 3）、**hook が ACTIVE を解放する実装に差し替えたら回帰 5 が落ちること**（Phase 4）。実スクリプトを 22 回起動する方式は踏襲しない。

## コンポーネント境界

```
  公式 Claude Code ───────────────────────────────────────────
   WT 作成 / 通常削除 / isolation: worktree / .worktreeinclude
                          │
                          │ WorktreeRemove・SessionEnd
                          │ （観測と stale 再検証の trigger のみ・
                          │   解放も削除も許可判定もしない・advisory）
                          ▼
  ccs = Resource Governor ────────────────────────────────────
   ┌──────────┐   ┌────────────┐   ┌──────────────────────────┐
   │ policy   │──▶│   slots    │◀──│ with-slot                │
   │ min 合成 │   │ 固定 cell   │   │ 取得 → 実行 → finally 解放 │
   └──────────┘   │ quarantine │   │ 再入 / timeout            │
   ┌──────────┐   └────────────┘   └──────────────────────────┘
   │ domain   │──▶ domain-local store（cross-domain 共有なし）
   └──────────┘
                          │
                          ▼
  ccs = Quality Layer ────────────────────────────────────────
   真理値表（純粋関数）/ doctor（閉集合・報告のみ）/ 回帰 fixture

  project adapter 境界（MVP 外・下流が実装）
   ブランチ規則（release/stg・feature/*）/ migration 直列 / 作業台帳連携
```

**依存の向き**: `policy` と `domain` は他に依存しない。`slots` はこの 2 つと fs にのみ依存。`with-slot` が束ねる。公式 hook からは `slots` の**再検証 API だけ**を呼ぶ（**通常解放 API は呼ばない**。逆向きの依存も作らない）。

## MVP で作るファイル

```
.claude/scripts/wt/policy.mjs        上限の解決（min 合成・不在=組み込み既定 / 破損=1）
.claude/scripts/wt/domain.mjs        executionDomain の判定と domain-local store の解決
.claude/scripts/wt/slots.mjs         固定 cell の atomic 取得・自 owner の解放・quarantine 回収・真理値表
.claude/scripts/wt/with-slot.mjs     heavy / runtime コマンドのラッパ（取得 → 実行 → finally 解放・timeout・再入）
tests/fixtures/wt-slots/cases/*.json      真理値表と policy 合成の網羅（実プロセスなし）
tests/fixtures/wt-slots/expected/*.json   凍結した期待値
tests/fixtures/wt-slots/replay.sh         純粋関数の回帰
tests/fixtures/wt-concurrency/replay.sh   並行性 4 点（Phase 3 = 回帰 1〜4: 上限厳守 / quarantine との取得競合 / stale 同時回収 / SIGKILL 後の回収）
```

**MVP に含めないもの（Phase 4 以降）**: doctor 本体（`doctor.mjs` 等）、公式 hook（`WorktreeRemove` / `SessionEnd`）への配線、`.claude/settings.json` の hooks 追記、`/weekly-inventory` からの doctor 呼び出し、**回帰 5（SessionEnd trigger が ACTIVE を解放しないこと）**、**command timeout の統合**。MVP のファイルは上記 4 本 + fixture 2 系統だけである。

既存ファイルへの追記は `.claude/docs/worktree-guide.md`（共有リンク禁止と、ライフサイクルは公式に委譲する旨）のみ。**新しい rule ファイル・新しい skill ディレクトリ・新しい user-invocable スキルは作らない**（ADR-0018）。

実装言語は Node（**組み込みモジュールのみ・依存パッケージなし**）とする。Claude Code 自体が Node を要求するため常に存在し、`O_EXCL`・atomic rename・PID 生存確認を追加依存なしで扱える。**子プロセス起動は `process.execPath` を使う** — Windows では `node_modules/.bin` の shim が `.cmd` であり、`shell:false` の spawn は EINVAL で失敗する（`existsSync` は大小無視 FS のため事前検出もできない）。shell を有効にして回避しない。

## 今回作らないもの

**前版にあり、本版で削除した**:

- WT 作成コマンド（`wt start`）— 公式へ委譲
- node_modules 準備コマンド（`wt equip`）— 利用者 / package manager へ
- WT 削除コマンド（`wt close --apply`）— 公式へ委譲。**公式管理の WT を削除する独自 CLI を作らない**
- **ownership lease** — 公式のセッション / WT ライフサイクルが持つ情報の写し書きになるため廃止
- **通常 WT 向けの独自 GC**（全 WT 走査の掃除器）— doctor を閉集合・報告のみに縮小
- **Cold / Ready / Running を制御の中心に置く設計** — 診断語彙に降格（決定 6）
- close の破壊前条件 8 項目・ホワイトリスト・破壊直前の再検証・`--force` 禁止 — **破壊操作を持たないため不要**
- `lease.mjs` / `inspect.mjs` / `verdict.mjs` / `cli.mjs` — 上記の廃止に伴い不要
- 実 Git の end-to-end テスト — ccs が git を操作しなくなったため不要

**もともと非目標（維持）**:

- カンバン UI / 独自の監視ダッシュボード（`claude agents` を第一候補とする）
- 夜間オーケストレーター
- プロセスの自動 kill（検出しても殺さない）
- WSL 移行 / cross-domain の枠統合
- メモリ・CPU に応じた枠の動的調整
- プロジェクト固有の adapter 実装（決定 9）

## 段階導入計画

| Phase | 内容 | rollback |
|---|---|---|
| **1. ADR** | 本 ADR の承認 | — |
| **2. characterization（scratch）** | 公式 WT 挙動を scratch 環境で一次確認する。**実施済み（CLI 2.1.238）** — 結果は前提表に反映。生データは追跡ツリーに置かない（ADR-0030） | 観測のみ・変更なし |
| **3. Resource Governor（ccs 実装）** | policy / domain / slots / with-slot と fixture テスト。公式 hook への配線はまだ行わない | ファイル削除で可逆（既存機構に未接続） |
| **4. ccs dogfood** | ccs 自身の重いコマンド（テスト・型チェック）を `with-slot` 経由にする。Phase 2 の結果が良ければ hook 配線を追加 | ラッパを外すだけ |
| **5. ARC dogfood** | ARC で併存運用。adapter が要る要求（ブランチ規則等）をここで洗い出す（実装は別 ADR） | 併存のため既存経路は無傷 |
| **6. BizIQ dogfood** | 2 プロジェクト目での確認 | 同上 |
| **7. 旧掃除器の縮小** | 現行掃除器から、公式と Resource Governor が担う部分を削る。**全撤去は最後**で、legacy doctor の対象（決定 7 の閉集合）は残す | 併存を維持したまま段階的に縮小 |

**Phase 3 の受入条件**: **並行性の回帰 1〜4 が緑**であること（回帰 5 は Phase 4）、policy の縮退が実走で確認できること、fixture テストが 1 秒未満で回ること。**WT 本数・プロセス数に実行時間が依存しないこと。**

**Phase 4 の受入条件（追加分）**: **回帰 5**（`SessionEnd` 相当の trigger 時に子プロセスが生存していれば cell が残る）が緑であること。

## 既知の限界（この ADR が閉じないもの）

1. **cross-domain の枠は保証されない**: `os.tmpdir()` も `~` も WSL と Windows で別実体であり、PID も別名前空間である。store は domain-local で、**他 domain の cell は観測すらされない**。Windows で 1 本・WSL で 1 本の heavy が同時に走る状態は防げない。
2. **ラッパを経由しない重い処理は数えられない**: 利用者が手で起動したコマンド、公式 hook が発火しない経路、別ユーザー・別コンテナの実行は slot を消費しない。**枠は「ccs 経由で起動されたもの」に対してのみ成立する。**
3. **`resource-policy.json` は敵対的改変を防がない**: 同じユーザー権限で動く agent は到達できる。守っているのはリポジトリ経由の drift と事故であり、権威分離ではない（ADR-0032 の「既知の天井」と同じ位置）。
4. **`ACTIVE_EXPIRED` は自動では解けない**: 期限更新に失敗したまま生き続けるプロセスがあると枠が 1 つ埋まったままになる。doctor が可視化するが、解放は人間の判断に残る（自動回収は二重割り当てを招くため採らない）。
5. **秘密 token は owner process tree 内にのみ継承される**: 外側の `with-slot` が生成し、子へは環境変数で継承されるが、tree の外には存在しない。owner が死ねば token も消えるため、**その cell を通常解放できる主体は以後いなくなる**。回収は stale recovery だけが行う（設計どおりだが、`ACTIVE_EXPIRED` に落ちた cell は「既知の限界」4 のとおり自動では解けない）。
6. **上限の解決値が不一致な場合**: policy 編集中などで 2 プロセスが異なる `N` を解決すると、大きい view を持つ側が余分な cell を取れる。同一ファイルから解決する限り実害は小さいが、厳密には解決値を cell に記録して照合する必要がある（Phase 3 の実装判断）。
7. **公式挙動はバージョンに紐づく**: 本 ADR の前提は **Claude Code 2.1.238** で characterization 済みである。将来の CLI 更新で **hook の payload・発火経路・WT の削除挙動・`claude agents` の出力**が変わりうる。**ccs のリリース時、または対応 Claude Code 版を更新する時に characterization を再実行する**。現在の既知制約として、**`WorktreeRemove` が発火しない経路がある**ことと、**`claude agents` の一覧が in-process subagent を含まず不在証明に使えない**ことを残す。

## 既存 ADR との整合表

| ADR | 要求 | 本 ADR での扱い |
|---|---|---|
| **0027**（公式スキル採用とラップ配布） | 公式が持つ機構は公式に委ね、ccs は縮約する | 本 ADR の中核。WT ライフサイクルを公式へ委譲し、ccs は公式が扱わない資源統治に縮約する（決定 1） |
| **0018**（目的・最小ループ 3 動詞） | 利用者が覚える接点を増やさない | 新 slash skill ゼロ。`with-slot` は重いコマンドのラッパとして配管に入り、利用者は意識しない。doctor は `/weekly-inventory` から呼ぶ |
| **0015**（下流の ccs 不意識運用） | 手動手順を配らない・完結性 | 下流は Resource Governor の存在を意識せず恩恵を受ける。移行時の手動手順をリリースノートに書かない |
| **0023**（文脈経済） | 決定的検査を LLM の前に | 判定は純粋関数で行い、LLM に資源状態を推定させない。doctor を hot path に置かない（決定 7） |
| **0032**（enforcement は fail-closed） | 判定不能は停止側・天井を明示する | 真理値表の INDETERMINATE は回収しない（決定 4）。policy 破損は 1 へ縮退（決定 2）。公式 hook は advisory として分類し正しさの根拠にしない（決定 5）。**権威分離は満たさない**ことを「既知の限界」3 に明記 |
| **0031**（現在状態オラクル） | 時点根拠 ≠ 現在の真・写し書き禁止 | ownership lease を廃止（決定 4）。WT の状態・PR 状態を保存せず derive する（決定 6） |
| **0002**（ブラックリスト方式） | 危険なものだけ止める | ccs が破壊操作を持たないため、本 ADR の範囲で禁止事項が増えない |
| **0030**（内部計画文書の非配布） | 計画・診断を git 追跡ツリーに置かない | 本 ADR は決定のみを持つ。実装手順書・characterization の生データは追跡ツリーに置かない |
| ARC **0160 決定 3**（台帳は derive 可能値を持たない） | 写し書き禁止 | 決定 4 で継承（cell は最小情報のみ）。ARC の台帳スキーマ・seal・監視塔は持ち込まない |
| ARC **0160 決定 4**（人間側意図 AND 機械側事実） | 両方が「消してよい」と言ったものだけ | **本 ADR では該当しない**（ccs が削除しないため）。削除の可否判定は公式と利用者に残る |

## 代替案と却下理由

| 案 | 却下理由 |
|---|---|
| ccs が WT manager を実装する | 公式が同じ対象を扱う以上、二重管理になり追随コストを下流全体が負う。ADR-0027 に反する |
| 公式管理の WT を ccs の CLI で削除する | 公式のライフサイクルと状態がずれる。破壊操作を持てば破壊前条件・再検証・ホワイトリストの機構が必要になり、**持たなければ不要**な複雑さを抱え込む |
| ownership lease を維持し「誰の作業か」を ccs が持つ | 公式のセッション / WT ライフサイクルの写し書きになる。ずれた瞬間に、業務上「使用中」の WT が ccs 側で「空き」に見える |
| Cold / Ready / Running を枠の判定に使う | 状態推定を制御パスに入れると、推定の誤りが資源の誤割当になる。cell の属性だけで閉じるほうが検証可能 |
| 一意 token + 占有数の計数で枠を守る | count と create の間の競合で上限を超える（決定 3）。数えてから作る限りこの窓は消せない |
| stale cell を検証してから削除する | 2 プロセスが同時に STALE 判定して両方が回収し、両方が取り直して上限を超える。quarantine への atomic rename を先行させる（決定 3） |
| 公式 hook を許可・拒否の判定に使う | hook が公式の操作を止める設計は、hook の障害が公式機能の障害に化ける。解放と観測に限定し advisory とする（決定 5） |
| quarantine 中の index を空きとして取得可能にする | 回収対象が ACTIVE と判明して戻すとき、戻し先が既に埋まっている。その瞬間 index に 2 本が併存し上限を破る。quarantine も占有として数える（決定 3） |
| 公式 hook で session ID / worktree key を根拠に cell を解放する | 同じ session ID の別プロセスや WT を共有する別セッションが、生きている cell を解放できる。解放権限は秘密 token に紐づける（決定 5） |
| doctor を pre-commit / pre-push に配線する | WT 本数の増加が日常操作の遅延に直結する。背景 1 の再生産（決定 7） |
| ブランチ規則を ccs コアに入れる | 1 つでもプロジェクト固有の分岐を入れると、以後すべての下流がそれを引き受ける。adapter 境界に置く（決定 9） |

## 影響

- 新規: `.claude/scripts/wt/`（**4 ファイル**）、`tests/fixtures/wt-slots/`、`tests/fixtures/wt-concurrency/`
- 追記: `.claude/docs/worktree-guide.md`（共有リンク禁止・ライフサイクルは公式へ委譲）
- **MVP（Phase 3）の範囲**: 上記 4 ファイル + fixture 2 系統のみ。**doctor と公式 hook 配線は MVP に含まない**
- **Phase 4 以降の配線**: 重いコマンドの `with-slot` 経由化、公式 hook（観測・再検証 trigger）の配線、doctor 本体の追加と `/weekly-inventory` からの呼び出し
- 下流: Phase 5 以降。現行掃除器は併存させ、縮小は最後
- 今後注意すべき点: 枠の既定値（heavy=1 / runtime=2）は**未実測の初期値**である。実測前に「効果があった」と述べない。引き上げる場合は空きメモリとセットで判断する（実装事例では 3 本並列で約 5GB を消費し、空き 4.5GB で fork 失敗が発生している）
