# jsonmbt — typed JSON source files for MoonBit（.json.mbt）

> 状态：**计划书 v0.1**（2026-10-06 立项）· 探针四线全绿（2026-10-05/06）· MVP 未开工
> 格式：`.json.mbt` · 包：`rustin-beep/jsonmbt` · CLI：`jsonmbt`

---

## 0. 一句话

**`.json.mbt` 是 JSON 的类型化源码形态**——以 MoonBit 子集表达的 JSON 数据，`moon check` 即 schema 验证、`moon fmt` 即格式统一，经 jsonmbt 引擎**降级输出干净、安全、确定性的 `.json`**。TS→JS 的关系，在 JSON 世界的复刻。

## 1. 是什么

三段式定义（探针实证过的边界）：

1. **格式 = MoonBit 子集**：`struct` 定义 + `let` 字面量值。`.json.mbt` 是合法 MoonBit 源文件——moon 全家桶（check/fmt/info）零适配白嫖：
   - 类型即 Schema：字段类型/必填编译期验证，错误信息 IDE 级（探针 B 实测：`Expr Type Mismatch / has type: String / wanted: Int` + 行列指向）
   - 重复键结构性不可能（record 重复 label 编译错）
   - 注释/尾逗号/格式统一天然合法
2. **求值分级**（核心规范，表达力 vs 可 diff 性的张力控制）：
   - **L0 纯字面量**（MVP）：结构+值，零计算——diff 最友好基线
   - **L1 常量算术**（二期）：`port: 4000 + 43`
   - **L2 let 绑定引用**（二期）：单文件内 `let base = 443` → `port: base`
   - **禁用**：函数、条件、跨文件引用、任何副作用——保住"所见即所得"
3. **降级单向无损**：`.json.mbt` → `.json` 确定性投影（类型名剥除、字面量直译）；反向不做（JSON→.json.mbt 需凭空造类型，伪需求）。

## 2. 为什么（立项依据，全部一手实测 2026-10-05/06）

1. **生态空白**（探针扫描）：JSON **解析**赛道有人（moonbitstack/moonjson 476 下载 = 读 JSON/JSONC/JSON5 四方言；官方 moonbitlang/jsonl 25k + json_deriving = 代码内编解码），但 **".json.mbt 类型化数据源格式 + moon 工具链集成 + 降级输出"确认无主**——moonjson 是"读别人的 JSON"，jsonmbt 是"让 JSON 有类型、注释和全套工具链"，错位共存；
2. **官方在投资类型化 JSON 方向**（json_deriving 的存在证明赛道有效），jsonmbt 与 json_deriving 互补（数据文件 vs 代码内转换）；
3. **工具链维护税外包**：fmt/check/info 是 moon 官方件——格式噪音归零（diff 诉求原点）与类型验证两大卖点不用自己造；
4. **命名三界无主**（实测）：mooncakes 与 GitHub 双零命中。

## 3. 有什么用（对谁）

- **MoonBit 开发者**：配置/测试快照/数据文件的类型安全 + diff 格式噪音归零；
- **JSON 重度场景**（LLM 配置、API 快照、CI 数据）：确定性输出 + 可审计 diff；
- **Vitro 协同**：第二个 wasm-gc 引擎（"引擎族"）、诊断方法论第二消费者（验证可迁移性）、demo 互导流；
- **比赛申报**：名额二候选（独立仓 rustin-beep/jsonmbt，与 Vitro 非拆分）；如 linter 出山，jsonmbt 作为主仓 0.9.0 伴生件——两条路都通。

## 4. 与 Vitro 的继承边界（**继承语言，不继承口音**）

| 继承 ✅ | 不继承 ❌ |
|---|---|
| J 系错误码稳定编号体系 | 教学卡默认全展开形态 |
| 位置精度（行列 + end 指向） | CLI 输出 emoji |
| 一行修复建议（help: ...） | "常见原因"默认内联 |
| 诊断内容资产（按需获取） | 教学定位本身 |
| 正/负样本锚纪律 | — |

**三层诊断形态**：
```
默认（一行）：config.mbt:3:9 [J3004] field 'port' expects Int, got String
  help: change "443" to 443, or change the field type to String
按需（--explain J3004 / 链接）：教学全文 + 常见原因
在线页/详情面板：完整诊断卡（emoji + Vitro 风格全展开）——教学卡的家在这里
```

## 5. 里程碑

| 阶段 | 内容 | 验收锚 | 状态 |
|---|---|---|---|
| P0 探针 | 生态扫描 + moon 四件套行为矩阵 + 类型诊断采样 + parser→JSON 管道 | 管道输出合法 JSON（实测 ✅ 2026-10-06） | ✅ |
| P1 MVP | L0 子集校验 + 降级输出器 + CLI（`jsonmbt build/check`）+ 正负样本锚 | 端到端：`.json.mbt` → 合法 `.json` 逐字节确定；类型错误诊断 ≤1 行 + help；10+ 样本锚 | 目标 2–3 周（兼职） |
| P2 发布 | mooncakes `rustin-beep/jsonmbt@0.1.0` + 在线试玩页（wasm-gc，Pages） | 双出口同构输出（native/wasm-gc）；在线页可粘贴转换 | P1 后 |
| P3 完整 | L1/L2 求值分级 + `&` 去重/展开 + diff 模式（两文件语义 diff）+ 大数策略落地 | L1/L2 探针锚 + diff 输出人工验收 | P2 后 |
| P4 生态 | JSON Pointer / 与 json_deriving 联动声明 / 规则手册 | — | 远期 |

## 6. 技术决策记录

| 决策 | 裁定 | 依据 |
|---|---|---|
| AST 节点名 | struct 字面量 = `Expr::Record(type_name~, fields~)`（全 labeled pattern）；字段 = `FieldDef{label : Label(struct), expr}`；字面量 = `Constant::Int/Double/Bool/String` **源文本直传** | parser@0.4.3 mbti 校准（2026-10-06 探针） |
| 降级输出后端 | 字符串直拼（探针已出合法 JSON）；x/json 大数行为探针 D 待补 | — |
| 大整数 | **超 2⁵³ 编译错（默认）**；字符串化需字段级标注——Snowflake ID 坑（Twitter ID 问题）写进规范 v0 | JSON 经典坑前置规避 |
| 出口 | native（CLI 主，单 exe 零依赖）+ wasm-gc（在线页）+ js（老浏览器兜底） | 一段代码四出口 = README 首段的 MoonBit 卖点 |
| 命名 | 格式 `.json.mbt`（品牌不变量）/ 包+仓 `rustin-beep/jsonmbt`（独立于 vitro owner，通用工具不做教学定位切割）/ CLI `jsonmbt` | owner=产品名重合会产生定位错位噪音；vitro owner 留给教学式诊断家族（engine + 未来 lint） |
| 竞品边界 | moonjson（解析方言家族）= "读"；jsonmbt = "写 + 类型 + 工具链"。README 需主动声明共存而非竞争 | 探针扫描定论 |

## 7. 风险登记表

| # | 风险 | 概率 | 对冲 |
|---|---|---|---|
| R1 | moon 工具链 breaking 影响 .json.mbt 行为（文件发现/fmt 形态变化） | 中 | 探针行为矩阵固化为本仓测试锚（P1 起）；moonbit 升级手册同款流程 |
| R2 | 求值分级被"加功能"诱惑突破 → diff 可读性死亡 | 中（自律风险） | 分级写进规范 v0 为冻结条款；新能力提案需独立评审 |
| R3 | 大数/转义边角坑（Int64 精度、非法 UTF-8、代理对） | 高（一定会遇到） | 每项进负样本锚；大数默认编译错已裁定 |
| R4 | 采用率：用户为何弃 JSON5 | 存在 | 主打 diff 工具链体验差（fmt+check+确定性三件套 JSON5 给不了）；MoonBit 生态内首发卡位 |
| R5 | 官方未来内建 typed-json 格式 | 低-中 | 规范与 MoonBit 类型系统深度绑定（官方做超集格式可能性远低于做 linter）；即便内建，CLI diff 工具链仍是独立价值 |

## 8. 探针存档（证据链）

- 探针环境：`D:\code\mbt-lint-probe`（parser@0.4.3 管道 + expr_to_json 原型，main.mbt 探针 C 可复跑）
- `.json.mbt` 样本与四件套行为：`D:\code\jsonmbt_probe`（check 0 错 / fmt 字段对齐 / info 生成 `pub let server : Server` 接口面 / 类型错误诊断实测）
- 生态扫描与竞品定位：moonbitstack/moonjson（读方言家族）、官方 jsonl+json_deriving（编解码）、确认无 ".json.mbt 源格式"同类
- 关联记忆：next-project-candidates-verdict-20261005（三候选终局）、bugfix-include-batch-20261005（include 管线知识）

## 9. 边界声明

jsonmbt 是通用开发工具，**不是教学产品**——教学式诊断风格是设计选择而非定位声明。它也不是 JSON 的替代品推广：`.json` 仍是机读标准形态，`.json.mbt` 只服务"人写 JSON"的场景。
