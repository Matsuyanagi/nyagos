﻿[English](./since_4.1_en.md) / Japanese

Since 4.1
=========

NYAGOS 4.0 では、パイプライン等で実行される複数の goroutine から
同一の Lua インスタンスを呼び出すことがあり、Lua API 呼び出し時に
panic を起こす問題がありました。

NYAGOS 4.1 では、それを回避するために、コマンド発行の度に別の
Lua インスタンスを新規に作成して、Lua インスタンスの競合を回避し、
安定をはかりました。

ただし、別のインスタンスでは、変数・テーブル領域が完全に別になり、
このままでは nyagos.alias[] 等に代入された関数自身すら、新しい
Lua インスタンス(goroutine)から見えないという問題があります。

そのため、グローバルテーブル nyagos[] 以下と share[] 以下に代入された
変数・関数については、Go言語側で保持し、新インスタンスの同テーブルより
参照できるようにしました。

とはいえ、これによって、従来稼動していた Lua スクリプトの互換性が
損われる結果となりました。NYAGOS 4.0 で動作していたスクリプトが
4.1 にて同様に動くには、下記の修正が必要です。

- 従来グローバル変数に代入していた変数を、share[] 下へ移動する
    - share 直下の変数・関数は、全ての Lua インスタンス・
      コマンドより参照可能
    - 変更の検出は share[] の直下しかされない。つまり
      `share.foo = { '1','2','3' }` は OK だが、
      `share.foo[1] = 'x'` という変更は階層が一つ深いため、
      データ本体まで修正が届かない。正しく、反映するためには
      下記のように、テーブル全体を出し入れする必要がある。

```
local t = share.foo
t[1] = 'x'
share.foo = t
```

- `nyagos.alias[]` , `nyagos.on_command_not_found` には代入できるのは
  関数だけで、クロージャーは代入できない
    - つまり、local 宣言された変数も参照できない
    - `nyagos.prompt` も同様だが、改善を検討中

<!-- vim:set fenc=utf8: -->
