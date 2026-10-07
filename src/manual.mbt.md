# jsonmbt 使用手册（可执行文档）

> `.json.mbt` 是 JSON 的类型化源码形态：以 MoonBit 子集表达的 JSON 数据，
> `moon check` 即 schema 验证、`moon fmt` 即格式统一，经 jsonmbt 引擎
> **降级输出干净、安全、确定性的 `.json`**。
>
> 本文档的代码块是 `mbt check` fence——`moon test` 会逐块执行（文档即锚，
> 示例永不腐烂）。API 面来自本包 `pkg.generated.mbti`。

## 降级：`.json.mbt` → `.json`

`build_source` 接受源文本，产出**紧凑、键序 = 源序**的 JSON（类型名剥除、
字面量直译；数值保留源文本形态）：

```mbt check
///|
test "manual : build 基础形态" {
  let src =
    #|struct Server {
    #|  port : Int
    #|  host : String
    #|  tags : Array[String]
    #|}
    #|
    #|pub let server : Server = Server::{
    #|  port: 8080,
    #|  host: "localhost",
    #|  tags: ["a", "b"],
    #|}
  let json = @src.build_source(
    src,
    path="server.json.mbt",
    expected_name="server",
  )
  inspect(
    json,
    content="{\"port\":8080,\"host\":\"localhost\",\"tags\":[\"a\",\"b\"]}",
  )
}
```

CLI 形态：`jsonmbt build server.json.mbt` → 同目录 `server.json`；
`jsonmbt build -` 从 stdin 读、产物写 stdout。

## 摄取：JSON/JSONC → `.json.mbt`

`import_source` 做形状推断（形状签名判重 / D-1 空容器两级启发 /
D-2 大数上浮 / 键名逃生门），生成带 `@generated` 头的合法 `.json.mbt`：

```mbt check
///|
test "manual : import 推断（单样本 null 诚实拒绝）" {
  let ok = try {
    let _ = @src.import_source(
      "{\"port\": 8080, \"retries\": null}",
      path="config.json",
      stem="config",
    )
    "succeeded"
  } catch {
    e => if e is @src.Diag(..) { "rejected" } else { abort("non-Diag") }
  }
  // null 字段需非 null 样本聚 Option 基型——单样本无线索（J4003）
  inspect(ok, content="rejected")
}
```

```mbt check
///|
test "manual : import 生成形态（多样本 null → Option + 键名逃生门）" {
  let outcome = @src.import_source(
    "{\"items\": [{\"v\": null}, {\"v\": 7}], \"meta\": {\"x-tag\": \"v\"}}",
    path="config.json",
    stem="config",
  )
  inspect(outcome.content.contains("v : Int?"), content="true") // 组内聚合 → Option[Int]
  inspect(outcome.content.contains("pub struct Config"), content="true")
  // 连字符键（x-tag）所在对象走 Map 逃生门——同值类型整体 Map[String, V]
  inspect(
    outcome.content.contains("meta : Map[String, String]"),
    content="true",
  )
}
```

CLI 形态：`jsonmbt import config.json` → `config.json.mbt`；
`jsonmbt import config.json --check` 是幂等闸——磁盘产物与重算结果
**行尾归一后比对**，漂移即 rc 2（D-10 的有义分叉）。

## 校验：check = build 的 dry-run

`check_source` 与 build 走**同一条校验路径**（两套校验语义必漂移——D-8），
无任何写副作用。所有诊断走 stderr 机器可读前缀：

```mbt check
///|
test "manual : 诊断的机器可读形态" {
  let src =
    #|struct T {
    #|  port : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  port: "443",
    #|}
  let d = try {
    let _ = @src.build_source(src, path="t.json.mbt", expected_name="t")
    "no-error"
  } catch {
    e => e.render()
  }
  inspect(
    d,
    content="jsonmbt: error [J3004] t.json.mbt:6:9 expects Int, got String literal\n  help: change the field type to String, or remove the quotes",
  )
}
```

## 往返等价：规范化器 N

D-11 的往返锚语义：`N(build(import(J))) == N(J)`——N 做**值语义**规范化
（RFC 8259 数字是抽象数值：1 ≡ 1.0；键序不敏感；超范围大数按源文本保真）。
「1 ≠ 1.0 保留」属**降级输出侧**（源文本直传），两个维度分立：

```mbt check
///|
test "manual : N 值语义等价" {
  let a = @src.normalize_json_text("{\"v\": 1}")
  let b = @src.normalize_json_text("{\"v\": 1.0}")
  inspect(a, content=b) // N 层：1 ≡ 1.0
}

///|
test "manual : build 层文本保真" {
  let s1 = @src.build_source(
    "pub let t = 1",
    path="t.json.mbt",
    expected_name="t",
  )
  let s2 = @src.build_source(
    "pub let t = 1.0",
    path="t.json.mbt",
    expected_name="t",
  )
  inspect(s1 == s2, content="false") // build 层：源文本直传
}
```

## L0 类型面

字段类型全集：`Int`（32 位，真实编译界 2³¹−1）/ `Int64` / `Double` /
`String` / `Bool` / `Option[T]`（null → None、值 → Some）/ `Array[T]` /
`Map[String, V]`（键名逃生门）/ 自定义 `struct`。求值分级 L0（纯字面量）
冻结——任何计算（`1 + 2`、引用、条件）都是 J3001 fail loud：

```mbt check
///|
test "manual : L0 白名单 fail loud" {
  let src =
    #|pub let t = { "a": 1 + 2 }
  let d = try {
    let _ = @src.build_source(src, path="t.json.mbt", expected_name="t")
    "no-error"
  } catch {
    e => e.render()
  }
  inspect(d.contains("[J3001]"), content="true")
}
```

## J 系错误码速查

| 码段 | 语义 |
|---|---|
| J000x | 用法 / IO（rc 4） |
| J100x | 语法：.json.mbt（J1001）/ JSON 输入（J1002）/ 重复键（J1003） |
| J200x | 文档基数（D-7）与类型头：缺/多 pub let、stem 不符、深度、顶层声明、类型面外 |
| J300x | 值面：非 L0、Map 键、无对应字面量、类型不匹配、未知/缺失/重复字段 |
| J400x | importer 阻断：D-1 家族（空容器/全 null）、异构、超 Int64（D-2 诚实拒绝） |
| J4030 | tagged-enum 识别提示（hint 级，rc 0） |
| J500x | 漂移/差异（rc 2——`--check` 幂等闸首例） |

rc 五值表（D-10）：`0` 成功 / `1` 输入错 / `2` 检测到漂移或差异 /
`3` 保留 / `4` 用法·IO 错。

## 值域枚举与多行文本（§8 裁定 2026-10-07）

有限词表字段用 `enum` 表达——**拼错变体在 `jsonmbt check` 即红**（写时校验，
防线补位 moon `[4031]`）；降级投影 = 变体名字符串：

```mbt check
///|
test "manual : enum 值域（写时红）" {
  let src =
    #|enum Status {
    #|  VerifiedRun
    #|  Open
    #|}
    #|struct Ledger {
    #|  status : Status
    #|}
    #|
    #|pub let ledger : Ledger = Ledger::{
    #|  status: VerifiedRun,
    #|}
  inspect(
    @src.build_source(src, path="l.json.mbt", expected_name="ledger"),
    content="{\"status\":\"VerifiedRun\"}",
  )
}
```

```mbt check
///|
test "manual : 拼错变体即红" {
  let d = try {
    let _ = @src.build_source(
      "enum S { A }\nstruct T { s : S }\npub let t : T = T::{ s: B }",
      path="t.json.mbt",
      expected_name="t",
    )
    "ok"
  } catch {
    e => if e is @src.Diag(..) { e.render() } else { "non-diag" }
  }
  inspect(d.contains("has no variant 'B'"), content="true")
}
```

长文本用 `#|` 多行字符串（每行净内容以 `\n` 连接降级）：

```mbt check
///|
test "manual : #| 多行文本" {
  let out = @src.build_source(
    "pub let m = #|第一行\n#|第二行",
    path="m.json.mbt",
    expected_name="m",
  )
  inspect(out, content="\"第一行\\n第二行\"")
}
```

**边界**：带 payload 构造器（`E(3032)`）v1 不支持（降级投影无自然 JSON
形态——建模为全变体 `E3032_UnknownChar` 或 struct 字段）；裸构造器无
类型上下文时语义不明，保守拒绝。
