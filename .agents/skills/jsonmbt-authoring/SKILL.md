---
name: jsonmbt-authoring
description: ".json.mbt 类型化 JSON 数据文件的手写与机器生成指南——四命令、子集规则、enum 键集建模、emitter 纪律、round-trip 兜底。Use when authoring or editing .json.mbt files, wiring jsonmbt into a repo's CI or freeze loop, migrating .json data sources, or debugging J-codes. 触发词：jsonmbt、.json.mbt、类型化 JSON、数据真相源、J3004/J4011、round-trip"
---

# jsonmbt 数据文件写作指南

`.json.mbt` = JSON 的类型化源码形态：**MoonBit 子集写数据，确定性降级回 JSON**。类型即 Schema——字段名拼错、类型不配、值越界在 `moon check` 编译期红（行列级），而非运行期。

## 心智模型

一句话：`.json.mbt` 是用 MoonBit 语法写的数据文件；`build` 是它的「另存为 JSON」；`moon check` 是它的「JSON Schema 校验器」。

## 四命令

```bash
jsonmbt import  x.json -o x.json.mbt      # 一次性迁移：JSON → .mbt（形状推断）
jsonmbt import  x.json --check            # 幂等闸：重导入必须逐字节一致（rc=2 漂移）
jsonmbt build   x.json.mbt -o x.json      # 确定性降级（同输入永同输出；失败零产物）
jsonmbt build   x.json.mbt -o -           # build 链纯验证：stdout 出件（check 不跑降级链）
jsonmbt check   x.json.mbt                # 只验不写（校验+内存构造，无降级 codegen）
```

`-o -` = 产物改道 stdout（build/import 通用；与 `--check`/`--fmt` 互斥——两者都是盘面语义）。CI 验证 build 链通不通用 `-o - | md5sum` 或 shell 层丢弃——**别用 `-o nul`**（挂 rename 语义报错）。

rc 语义：`0` ok / `1` 输入错 / `2` 漂移（--check）/ `4` 用法错。CI 闸按 rc 判红。

## 手写规则（子集边界——工具会在报错里重申，但前置知道少走弯路）

1. **类型即 Schema**：`struct` 定义即数据形状；`Option[T]` 字段 = 可空（`null` ↔ `None`）。改数据先看 struct；
2. **一个文件一个顶层文档**：`foo.json.mbt` 内有且只有一个 `pub let foo : ...`——**绑定名必须等于文件 stem**（J2003 会指路）；
3. **键集不齐的数组用带参 enum**（D-5）：每种键集一个 struct，`enum Case { A(Ax); B(Bx) }`，字面量 `A(Ax::{ field: value })`。降级投影 = tag 对象展开（payload 进顶层 + `"case"` tag 键）；**payload 字段禁止叫 `case`**（J3008 显式拒）；
4. **import 不自动转缺键异构**（J4010/J4011 fail loud）——拼错字段名与真可选无法区分，自动推断会把数据错误静默类型化。遇拒看报错里的字段集差异与分布计数，手工建模 enum 或补齐键；
5. **长文本用 `#|` 多行字符串**（D-12）——中文长描述不用拼 `\n`；
6. **大数 >Int64 拒收**（J4020）：降级要求无损——要保留超长数字请以 String 字段承载；
7. **全 null 列无法推断类型**（J4003）：至少给一个非 null 样本，或手工把字段建成 `Option[T]`；
8. **注释与尾逗号天然合法**——这是相对 JSON 的核心书写优势，用真注释写「这字段为什么存在」。

## 机器写回（emitter）纪律

1. **程序生成别走 import**——import 是人的迁移工具；直接产 .mbt 文本 + `jsonmbt build` 验证；
2. **Map 键序由 .mbt 文本序决定**：从 Go map range 直接输出会翻车（遍历序随机）——必须原文顺序抽取或显式排序，否则确定性破功；
3. **round-trip 是链路语义闸，必跑——但「round-trip 绿 ≠ 数据语义正确」**：它防的是**链路引入的漂移**（emitter 装错变体、编解码不对称、归一化丢信息——build 再生对拍即红）；**不防**：①手写源头错（靠 freeze diff 人审）②值超域（99999 稳定往返 99999，绿——需消费侧 guard 或值域校验）。另一个第二用途：emitter 形态版本升级时，round-trip 可证「纯形态重构、语义零变化」；
4. **fmt-stable**：import 用 `--fmt` 旗标（内部 spawn `moon fmt <单文件>`，无 workspace 副作用）；程序 emitter 同款——落盘后对产物单文件跑 `moon fmt`，不要对整个目录跑（会重排无关源文件）。**`--fmt` 前提 = 产物目录向上可达 moon workspace 根**（moon fmt 单文件只认 workspace 覆盖，盲区文件 moon 自报 `not in a Moon project` 退非零）；**fmt 失败 = 产物保留未 fmt 形态 + rc=4**（半成功态：脚本按 rc 判红，产物留现场供排查，别删也别信其形态）。

## Agent 协作纪律（下游仓收录时抄这段）

- **只改 .json.mbt 真相源**；再生的 .json 通常已 `.gitignore` 遮蔽或属读侧产物——改错侧 = 白改；
- 修改流程：改 `.mbt` → `jsonmbt check`（或 `moon check`）→ `jsonmbt build` 再生 → 提交两者（若 .json 入仓）；
- 看到文件头 `// @generated ... 禁手改（再生成：...）`：这是机器写回面——**不要手改**，跑头部标注的再生命令；
- 改坏不慌：所有错误是编译期行列级（J 码 + help 指路），按 help 修即可；数据错误不会静默落盘（build 失败零产物）。

## 常见 J 码速查

| 码 | 含义 | 处置 |
|---|---|---|
| J2003 | 绑定名 ≠ 文件 stem | 改绑定名或文件名 |
| J3004 | 字段类型不配 | 按 expects/got 修字面量 |
| J3006 | record 缺必填字段 | 补字段（Option 字段写 `None`） |
| J3008 | tag 键与 payload 字段撞车 | payload 字段改名 |
| J4002 | 空对象无从推断 | 至少一个字段，或手工建模 |
| J4003 | 全 null 列类型未知 | 给非 null 样本或手工 `Option[T]` |
| J4010/J4011 | import 遇缺键异构 | 看 D-5 字段集差异报告，手工建模 enum |
| J4020 | 整数超 Int64 | 改 String 字段承载 |
