<div align="center">
  <img src="assets/banner.svg" alt="jsonmbt — typed JSON source files for MoonBit" width="640">
</div>

# jsonmbt

**`.json.mbt` 是 JSON 的类型化源码形态**——以 MoonBit 子集书写的 JSON 数据：`struct` 头即 schema，值体即数据，经 jsonmbt 引擎**确定性降级**输出干净、紧凑的 `.json`。

TS→JS 的关系，在 JSON 世界的复刻：类型留在源文件里持续生效，产物是人人可读的标准 JSON。

```json.mbt
struct Server {
  port : Int
  host : String
  tags : Array[String]
  retries : Int?
}

pub let server : Server = Server::{
  port: 8080,
  host: "localhost",
  tags: ["a", "b"],
  retries: None,
}
```

```bash
$ jsonmbt build examples/server.json.mbt
```

```json
{"port":8080,"host":"localhost","tags":["a","b"],"retries":null}
```

- **类型即 schema，零新语法**：`.json.mbt` 是合法 MoonBit 源文件——`moon check` 编译期验证字段类型与必填性，错误信息 IDE 级（行列指向）；重复键结构性不可能；注释与尾逗号天然合法。`moon fmt` 直接统一格式。
- **确定性降级**：同一输入永远得到逐字节相同的输出。build 校验先行，失败零产物。
- **`Option` 即可空**：`Int?` ↔ JSON `null`，可空性写进类型头，读的人不用猜。
- **工具链零维护税**：fmt / check / IDE 支持全部继承 moon 全家桶，jsonmbt 只做「校验 + 降级」这一件事。

## 快速开始

依赖：[moon](https://www.moonbitlang.com)（MoonBit 工具链）与 clang（native 后端）。

```bash
MOON_CC=clang moon build          # 产物在 _build/native/*/build/cmd/jsonmbt/
```

CLI 当前动词面（P1）：`build` 与 `check`。

```bash
jsonmbt build <file.json.mbt...> [-o <out.json>]   # 降级输出，默认同名 .json
jsonmbt check <file.json.mbt...>                   # 只校验不产出（= build 的 dry-run）
jsonmbt build - < in.json.mbt                      # stdin 进，stdout 出
```

- 退出码：`0` 成功 / `1` 输入错 / `4` 用法·IO 错。
- 诊断走 stderr，稳定编号（J 系），一行定位 + 一行修复建议：

```
jsonmbt: error [J3004] examples/server.json.mbt:9:9 expects Int, got String literal
  help: change the field type to String, or remove the quotes
```

- 产物为紧凑 JSON，原子写（临时文件 + rename）落盘。

## 求值分级（L0–L2）

语言面按「表达力 vs 可 diff 性」分级，**L0 已实装，L1/L2 规划中**：

| 级别 | 能写什么 | 状态 |
|---|---|---|
| L0 纯字面量 | 结构 + 值，零计算 | ✅ 当前实现 |
| L1 常量算术 | `port: 4000 + 43` | 规划（P3） |
| L2 let 引用 | 文件内 `let base = 443` → `port: base` | 规划（P3） |
| — | 函数 / 条件 / 跨文件引用 / 副作用：**永久禁用** | 冻结 |

禁用计算保住「所见即所得」：降级对值无损且确定，diff 噪音归零。

## importer（规划中，P1.5）

`jsonmbt import x.json` 将从 JSON 反推 `struct` 头 + 直译值，生成合法 `.json.mbt`——存量 JSON 资产的迁移入口。P0 探针已用合成矩阵与真实数据完成实证（含 2,469 张冻结档案压测，未判形态全部落在已知逃生门内，详见 [PLAN §9](docs/PLAN.md)）。

## 路线图

| 阶段 | 内容 |
|---|---|
| ✅ P0 | 探针：生态扫描 / 行为矩阵 / importer 三映射 / 真实数据压测 |
| 🟡 P1 | L0 校验器 + 降级器 + CLI（build/check）——**主体已落地**，余项随 P1.5 收口 |
| P1.5 | importer v1 + `--check` 幂等闸 + 层 2 Go 黑盒防线 + mooncakes 发包 |
| P2 | npm 包（js 出口）+ 在线试玩页 + `jsonmbt schema` 导出 |
| P3 | L1/L2 求值分级 + diff 模式 |

进度细节以 [PLAN §5 里程碑表](docs/PLAN.md)为唯一载体——本表只是导览。

## 为什么不是 Jsonnet / JSONC / YAML

配置赛道已有玩家，但「数据格式的工具链 = 真实语言的工具链」这个组合空着：Jsonnet/Dhall/Nickel 为 fmt/LSP 自建全套（Dhall 的采用瓶颈正是工具链税），JSONC 有注释但无类型无降级，YAML 的产物是自己而非 JSON。jsonmbt 靠「MoonBit 子集」白嫖一条完整工具链，靠求值分级冻结对功能蔓延免疫。完整立项依据与先例矩阵见 [PLAN §2](docs/PLAN.md)。

## 工程

- 内层防线：`moon test` 语义锚（当前 28 锚全绿）；外层防线（Go 黑盒：CLI 进程契约 golden、确定性断言、压测）随 P1.5 落地——对外承诺的真防线在层 2。
- 诊断体系与正/负样本锚纪律继承自 [Vitro](https://github.com/rustin-beep/vitro)（继承语言，不继承口音）。
- MoonBit 工具链陷阱快照：[docs/MOONBIT_PITFALLS.md](docs/MOONBIT_PITFALLS.md)。

## 文档

- [docs/PLAN.md](docs/PLAN.md) — 计划权威：里程碑、决策记录（D 系）、探针存档
- [AGENTS.md](AGENTS.md) — 贡献纪律（红线：红→绿、诚实记录、求值分级冻结）
- [assets/](assets/) — 视觉资产（logo / banner，SVG 为源）

## License

[MIT](LICENSE)
