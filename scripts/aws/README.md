# S3 非公開データへのアクセス設計（タグ方式）

HiCarta のカタログに書くデータを、公開 URL だけでなく **非公開の S3 オブジェクト**
にも広げるための AWS 側の設定一式。2026-11-05 設計。

対象バケット: `uo-cgf`（us-west-2）。HiCarta 側の実装（`s3://` の署名付き読み込み）
は別途。この README は AWS 側だけを扱う。

## 考え方

- **置き場所はプロジェクト、権限はタグ。** フォルダ（プレフィックス）で権限を
  分けると、公開に切り替えるたびにファイルを移動しカタログの URL を書き換える
  ことになる。代わりに各オブジェクトに `access` タグを 1 つ付け、IAM ポリシー
  はタグで許可する。ファイルも URL もカタログも動かない。
- タグの値は 3 段階: `<ラボ名>` < `p01` < `public`（ラボ名のタグは複数作れる。現在は `noma` のみ）
  - `noma`   … 野間研メンバーのみ
  - `p01`    … P01 グループ全体（複数研究室）＋野間研
  - `public` … 誰でも（認証なしの https でも読める）
  - **タグ無し** … どのポリシーにも当たらないので誰にも見えない（安全側の既定）
- 誰が何を読めるかは **S3 が判断**する。HiCarta は鍵で署名して送り、403 なら
  「アクセス権がありません」と表示するだけ。レベルを増やしても HiCarta の
  コードは変わらない。

| 読む人 | 鍵 | noma | p01 | public |
|---|---|:-:|:-:|:-:|
| 野間研メンバー | NomaLabReaders グループの IAM ユーザー | ○ | ○ | ○ |
| P01 メンバー | P01Readers グループの IAM ユーザー | × | ○ | ○ |
| 一般（論文読者など） | 鍵なし | × | × | ○ |

## ファイル

| ファイル | 役割 |
|---|---|
| `policy-noma-reader.json` | IAM ポリシー: `access ∈ {noma, p01, public}` の GetObject を許可 |
| `policy-p01-reader.json`  | IAM ポリシー: `access ∈ {p01, public}` の GetObject を許可 |
| `bucket-policy-public.json` | バケットポリシー: `access = public` を匿名に許可 |
| `s3_set_access.sh` | プレフィックス（またはオブジェクト 1 つ）の `access` タグを一括設定 |
| `s3_list_access.sh` | プレフィックス配下のタグ一覧 |
| `s3_migrate_acl_to_tags.sh` | 初回のみ: 現在の ACL を見て public / noma のタグを付ける（既定は dry run） |

## 初回セットアップ（root ではなく管理用 IAM ユーザーで実施）

### 現状（2026-11-05 確認）
- バケットポリシー: なし（`NoSuchBucketPolicy`）
- Object Ownership: 未設定（`OwnershipControlsNotFoundError`）＝ ACL が有効な旧構成
- 公開は **オブジェクトごとの ACL**（`AllUsers READ`、`--acl public-read` でアップロード）

つまり今は「ACL が付いたファイルだけ公開、付いていないファイルは非公開」。
**一括で `public` タグを付けてはいけない**（ACL の無い非公開ファイルまで公開される）。
現在の ACL を 1 件ずつ見てタグを決める `s3_migrate_acl_to_tags.sh` を使う。

### 手順（この順番で）

```bash
# 0. 現在の Block Public Access を記録しておく
aws s3api get-public-access-block --bucket uo-cgf

# 1. ACL → タグの移行計画（dry run。何も変更しない）
./s3_migrate_acl_to_tags.sh s3://uo-cgf/
#    migrate_uo-cgf_<時刻>.tsv の件数（public / noma / read-error）を確認

# 2. 問題なければ適用
APPLY=1 ./s3_migrate_acl_to_tags.sh s3://uo-cgf/
./s3_list_access.sh s3://uo-cgf/P/020/ | awk '$1=="-"'     # タグ無しが残っていないか

# 3. 2 本の管理ポリシーとグループ、利用者ごとの IAM ユーザー（ACCOUNT_ID は 12 桁）
aws iam create-policy --policy-name HiCartaNomaLabRead --policy-document file://policy-noma-reader.json
aws iam create-policy --policy-name HiCartaP01Read     --policy-document file://policy-p01-reader.json
aws iam create-group --group-name NomaLabReaders
aws iam create-group --group-name P01Readers
aws iam attach-group-policy --group-name NomaLabReaders --policy-arn arn:aws:iam::ACCOUNT_ID:policy/HiCartaNomaLabRead
aws iam attach-group-policy --group-name P01Readers     --policy-arn arn:aws:iam::ACCOUNT_ID:policy/HiCartaP01Read
aws iam create-user --user-name hideki.tanizawa
aws iam add-user-to-group --user-name hideki.tanizawa --group-name NomaLabReaders
aws iam create-access-key --user-name hideki.tanizawa      # 出力の鍵を本人にだけ渡す

# 4. 公開用バケットポリシーを入れる（この時点では ACL とポリシーの二重で公開）
#    BlockPublicPolicy が true だと入らないので、先に false にする
aws s3api put-public-access-block --bucket uo-cgf --public-access-block-configuration \
    BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy --bucket uo-cgf --policy file://bucket-policy-public.json

# 5. ACL を無効化して、公開の経路をポリシー（＝タグ）だけにする
#    これ以降 ACL は一切評価されない。--acl public-read 付きのアップロードは
#    AccessControlListNotSupported エラーになる（黙って公開されるより安全）
aws s3api put-bucket-ownership-controls --bucket uo-cgf \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

# 6. 検証
curl -sI https://uo-cgf.s3.us-west-2.amazonaws.com/P/020/2023-08-01_juicer_020_condensin_domain_boundary_check.txt | head -1   # 200 のまま
#    noma のファイルを 1 つ選んで 403 になること、鍵ありの aws s3api head-object で読めることを確認
```

戻したいとき: 手順 5 は `ObjectOwnership=ObjectWriter` で元に戻せる（ACL は
消えずに残っているので、戻した瞬間に旧状態に復帰する）。

**移行後に直すスクリプト**: パイプラインの S3 ブロックなどで `--acl public-read`
を付けている箇所はすべて外し、sync 直後に `s3_set_access.sh ... noma` を呼ぶ。

利用者が辞める／鍵が漏れた → そのユーザーのキーを `aws iam delete-access-key`
で失効するだけ。他の人の鍵は影響を受けない（グループ方式にした理由）。

## ラボを追加するとき

1. `policy-noma-reader.json` をコピーし、`"noma"` を新しいラボ名に変える
   （許可リストは `["<ラボ名>", "p01", "public"]`）
2. `aws iam create-policy` → `create-group` → `attach-group-policy`（手順 3 と同じ）
3. `s3_set_access.sh` の `LABS="noma"` に名前を足す

P01 のポリシーとバケットポリシーは変更不要。

## 日常運用

```bash
# 新しいサンプルをアップロードしたら、まずラボ内限定に
aws s3 sync "$DIR_DATA/$NAME/" "s3://uo-cgf/P/020/$NAME/" --exclude '*' --include "$NAME.hic"
./s3_set_access.sh "s3://uo-cgf/P/020/$NAME/" noma

# 共同研究で P01 に開く / 論文公開後に一般公開
./s3_set_access.sh s3://uo-cgf/P/020/wt_Db_MHM_mix1/ p01
./s3_set_access.sh s3://uo-cgf/P/020/wt_Db_MHM_mix1/ public

# 閉じる
./s3_set_access.sh s3://uo-cgf/P/020/wt_Db_MHM_mix1/ noma
```

- `put-object-tagging` はタグ集合を **丸ごと置き換える**。他のタグを使う予定が
  できたらスクリプトを直すこと。
- **再アップロード（上書き）でタグは消える。** パイプラインの S3 ブロック
  （`sh/2026-08-21_hic_pipeline_rfy_hic2.sh` 等）の `aws s3 sync` の直後に
  `s3_set_access.sh ... noma` を呼ぶようにしておく。
- `aws s3 cp/sync` には `--tagging` が無い（`s3api put-object` にはある）ので、
  上書き後のタグ付けはこのスクリプトで行う。
- `ListBucket` は意図的に与えていない。鍵があっても一覧は見えず、存在しない
  キーも権限の無いキーも 403 になる（HiCarta 側は 403/404 を同じ扱いにする）。

## 利用者側（HiCarta を使う人）の準備

受け取った鍵を `~/.aws/credentials`（Windows: `%USERPROFILE%\.aws\credentials`）に置く:

```ini
[hicarta]
aws_access_key_id     = AKIA...
aws_secret_access_key = ...
```

HiCarta の config.txt で `aws_profile = hicarta` を指定（または設定ダイアログ）。
カタログの path 列は `s3://uo-cgf/P/020/<NAME>/<NAME>.hic` と書く。
公開データは従来どおり `https://...` でも、`s3://` のままでもよい（鍵が無ければ
署名なしで試す）。

## HiCarta 側の対応（2026-11-05 実装）

- `R/s3.R`（新規）: `s3://bucket/key` と S3 の https URL を認識し、AWS SigV4 で署名
  （`digest` の HMAC-SHA256。shiny に同梱なので追加インストール不要）。鍵は
  config.txt の `aws_profile` → 環境変数 `AWS_ACCESS_KEY_ID` → `AWS_PROFILE` →
  `[default]` の順に `~/.aws/credentials`（Windows は `%USERPROFILE%\.aws\credentials`）から読む。
- `https://` の S3 URL はまず署名なしで送り（従来と同じ）、403 のときだけ鍵で署名して再送。
  `s3://` は鍵があれば署名、無ければ署名なし。鍵が無効なら署名なしで再試行。
  リージョンは S3 の応答から自動補正。
- 配線: `.hic`/bigWig のストリーミング（`hic_reader.R` / `bigwig_reader.R`）、
  ダウンロードキャッシュ（`readers.R` `cache_local`）、カタログ（`catalog.R`）、
  IGV XML（`tracks.R`）。strawr / download エンジンでは `s3://` をキャッシュ経由で読む。
- 設定ダイアログに「AWS プロファイル」「AWS リージョン」と鍵の検出状況を表示。
- 403 は「権限なし」「非公開で鍵なし」「鍵が無効」「時計ずれ」を区別して表示
  （ListBucket を与えないので「存在しない」と「権限なし」は区別できない）。
- 検証: `Rscript scripts/test_s3.R [s3://...]` — AWS 公式の署名テストベクタ 3 件を
  含む 21 項目。既存の `test_hic_reader.R` / `test_bigwig_reader.R` は `s3://` で全項目通過。

### 学会後の動作確認（retreat 前に 30 分程度）

バケット全体の移行（ACL → タグ）は不要。既存の公開ファイルには影響しない。

```bash
# 1. ポリシー・グループ・自分の IAM ユーザー（上の「手順 3」だけ）
#    確認用に P01 側のテストユーザーも 1 つ作っておくと 403 の実演ができる
aws iam create-user --user-name test.p01
aws iam add-user-to-group --user-name test.p01 --group-name P01Readers
aws iam create-access-key --user-name test.p01

# 2. テスト用ファイルを ACL なしで置き、タグを付ける
aws s3 cp sample.hic s3://uo-cgf/O/test/sample_noma.hic
aws s3 cp sample.hic s3://uo-cgf/O/test/sample_p01.hic
./s3_set_access.sh s3://uo-cgf/O/test/sample_noma.hic noma
./s3_set_access.sh s3://uo-cgf/O/test/sample_p01.hic  p01
curl -sI https://uo-cgf.s3.us-west-2.amazonaws.com/O/test/sample_noma.hic | head -1   # 403 になること
```

3. PC の `%USERPROFILE%\.aws\credentials` に、**専用のプロファイル名**で鍵を書く
   （`[default]` に管理者の鍵が入っていると、それで全部読めてしまい確認にならない）:
   ```ini
   [hicarta]
   aws_access_key_id = AKIA...
   aws_secret_access_key = ...
   [hicarta-p01]
   aws_access_key_id = AKIA...
   aws_secret_access_key = ...
   ```
4. HiCarta フォルダで: `Rscript scripts/test_s3.R s3://uo-cgf/O/test/sample_noma.hic`
   （config.txt に `aws_profile = hicarta`）→ `HTTP 206 signed=TRUE` が出れば OK。
5. HiCarta の設定で AWS プロファイル `hicarta` → カタログの path に
   `s3://uo-cgf/O/test/sample_noma.hic` を書いて開く。
   プロファイルを `hicarta-p01` に変えると noma は「権限なし」、p01 は開ける。
