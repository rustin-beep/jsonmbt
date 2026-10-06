# jsonmbt — typed JSON source files for MoonBit（.json.mbt）

> 状态：**计划书 v0.3.1**（2026-10-06 立项，同日四轮修订：v0.2 importer 探针+竞品矩阵；v0.3 压缩比/YAML·TOML/真实数据压测/D 系终案/Go 直产；**v0.3.1 入口语义 D-7~D-11 + build 不变量 + 规范化器锚 + 勘误**）· **状态唯一载体 = §5 里程碑表**（本文件其他处不写进度时点句）
> 格式：`.json.mbt` · 包/仓：`rustin-beep/jsonmbt` · CLI：`jsonmbt`

---

## 0. 一句话与第一性原理

**`.json.mbt` 是 JSON 的类型化源码形态**——以 MoonBit 子集表达的 JSON 数据，`moon check` 即 schema 验证、`moon fmt` 即格式统一，经 jsonmbt 引擎**降级输出干净、安全、确定性的 `.json`**。TS→JS 的关系，在 JSON 世界的复刻。

**第一性原理（压缩/解压模型）**：`.json.mbt` 是浓缩语言，`build` 降级是解压，`import` 是压缩。**解压对值无损且确定；类型头/注释是压缩侧元信息，不进解压契约**（元信息留在源格式里持续生效是特性非缺陷——TS 编译成 JS 也"丢"类型，没人说 TS 有损）——本规范全部边界裁定由此推出：空数组=压缩时信息不足（诚实标注）；Int64=压缩时选更大容器（无损优先）；字符串化=改数据本身（违反值无损契约，只能显式 opt-in）。

**排他性定位（形态先例矩阵的唯一空位）**：数据格式的工具链 = **真实语言的工具链**——Jsonnet/CUE/Dhall/Nickel/KCL 全部为 fmt/LSP/IDE 自建全套（Dhall 的采用瓶颈即「集成、工具链、LSP 的完整体验」），jsonmbt 的 fmt/check/info/LSP 零成本继承 moon；加上求值分级（L0–L2 冻结条款）对功能蔓延的免疫。**逃生门原则**：json.mbt 表达不了的，写真 MoonBit 去（FFI/.wat 皆可）——那是隔壁房间，不是本格式的扩张理由；逃生门的存在让分级冻结变得可坚持（Go 的 cgo/汇编同理；Jsonnet 死于没有逃生门——所有需求都涌进 DSL 本体）。

## 1. 是什么

三段式定义（探针实证过的边界）：

1. **格式 = MoonBit 子集**：`struct` 定义 + `let` 字面量值。`.json.mbt` 是合法 MoonBit 源文件——moon 全家桶（check/fmt/info）零适配白嫖：
   - 类型即 Schema：字段类型/必填编译期验证，错误信息 IDE 级（探针实测：`Expr Type Mismatch / has type: String / wanted: Int` + 行列指向）
   - 重复键结构性不可能（record 重复 label 编译错）
   - 注释/尾逗号/格式统一天然合法
   - **语法实测补充**：record 字面量必须 `Server::{ ... }` 形态（裸 `Server { ... }` 报错 missing '::'）；record 字段位裸大整数字面量按期望类型定型（Int64 字段无需 L 后缀）；struct 定义字段换行分隔不收逗号、字面量收尾逗号
2. **求值分级**（核心规范，表达力 vs 可 diff 性的张力控制；分级冻结是求生不是保守——Jsonnet 功能蔓延是反面教材，逃生门原则见 §0）：
   - **L0 纯字面量**（MVP）：结构+值，零计算——diff 最友好基线
   - **L1 常量算术**（二期）：`port: 4000 + 43`
   - **L2 let 绑定引用**（二期）：单文件内 `let base = 443` → `port: base`
   - **禁用**：函数、条件、跨文件引用、任何副作用——保住"所见即所得"
3. **importer 摄取 + 降级单向**：
   - **降级**：`.json.mbt` → `.json` 确定性投影（类型名剥除、字面量直译）——方向单向
   - **摄取（importer）**：`jsonmbt import x.json` → 推断 struct（形状签名判重）+ 值直译，生成合法 `.json.mbt`。这是**摄取工具**不是语法反向（`.json` 不是 `.json.mbt` 的合法子集），桥由此搭上——存量 JSON 十亿级资产的迁移入口
   - 实测：10 样本合成矩阵 4 生成全绿 + 6 诚实拒绝；**Vitro 真实数据 44 张 19 裸 PASS / 25 REJECT 零死角**；**冻结分支 2469 张 48.1MB 全量压测 49% 裸 PASS、余下全部落在三个已实锤逃生门内（tagged-enum/空容器/动态键）——零未知形态**

## 2. 为什么（立项依据，全部一手实测）

1. **形态先例矩阵——市场已验证，空位确认**：

   | 先例 | 定位 | 体量 | 对 jsonmbt 的意义 |
   |---|---|---|---|
   | Jsonnet | 数据模板 → JSON | ~7k★，K8s/Grafana 在用 | 市场验证；功能蔓延 = R2 反面教材 |
   | CUE | 约束+统一 → JSON/OpenAPI | ~5k★ | CLI 动词面对齐对象；schema 导出设计参照 |
   | Dhall | total 类型化配置 | ~4k★ | **死因教训**：采用卡在「集成/工具链/LSP 完整体验」——自建工具链税是赛道通病，jsonmbt 白嫖 moon 零此税 |
   | Starlark | Python 确定性子集 | Google 系 | 「确定性语言子集」设计方法论的同类先例 |
   | Nickel/KCL | 新一代配置语言 | 新 | 赛道仍活跃；「又一个 DSL」难出头——「不是 DSL」是唯一差异化 |
   | **JSONC/JSON5** | JSON+注释（弱格式） | VS Code 承载 | **不做同类物**（自建工具链=Dhall 死因 + 正面撞在位者）；importer 支持 JSONC/JSON5 输入作迁移桥梁 |
   | **TypeScript satisfies** | `const x = {...} satisfies T` | TS 主流实践 | **需求存在最强证据**：类型化数据文件是真需求；jsonmbt 补上它缺的确定性降级一环 |

2. **JSON→MoonBit 类型推断有人做过但形态不构成威胁**：[gmlewis/json-to-moonbit](https://github.com/gmlewis/json-to-moonbit)——停更两年（toolchain 锚 2024-09）、1 star、纯片段生成器、**无「转回 JSON」闭环**。方向被验证过；差异化恰在「源格式 + 闭环」。
3. **schema 赛道四玩家全部错位**：typify.mbt、mizchi/jsonschema（5K 下载，**明确不支持从样本推断**——API 面已核实）、MoonJTD、moon_zod。输入全是 schema 不是数据文件。quicktype 的 20+ 目标语言无 MoonBit。`jsonmbt schema` 导出（P2）后四玩家变下游。
4. **vs YAML/TOML（人写配置在位霸主）——不同价值轴**：① **产物轴**（最硬）：YAML/TOML 的产物是自己；.json.mbt 的产物是 **JSON**——API 快照/testdata/CI 数据等「终态必须是 JSON」的场景 YAML 根本不参赛；② 类型轴：无 schema 无类型 vs 类型即文件头；③ 坑位对照：YAML 的 Norway 问题/隐式转换/缩进敏感、TOML 深嵌套 `[a.b.c]`/`[[x]]` 都是要学的语法——「不用学」是神话，区别只在显性还是踩坑式；④ 工具链轴：每语言生态各养解析器 vs 白嫖 moon 全家桶。
5. **「要学 MoonBit 子集」的反驳**：学的不是 MoonBit 是五个形态（struct/let/T::{}、[...]、四标量）；值体与 JSON 同构度高（`{port: 443}` ≈ `{"port": 443}`）；**语法由工具承载**——importer 生成类型头，人只改值；类型头兼职 schema 文档（JSON 要等价能力得额外学 JSON Schema，难十倍）。
6. **工具链维护税外包** + **命名三界无主**（`.json.mbt` 源格式 + 降级闭环 + 工具链白嫖的组合确认无主）。

## 3. 对谁（受众漏斗）

- **MoonBit 开发者**：配置/测试快照/数据文件的类型安全 + diff 格式噪音归零（第一波）；
- **JSONC 注释痛者**：「想给 JSON 加注释」的巨大存量——L0 全覆盖还多给类型和 fmt（第二波，importer 的 JSONC/JSON5 输入拆进入成本）；
- **非 MoonBit 生态**（五条路径，依赖从浅到深）：
  1. **产物消费者**（零感知层，量最大）：读 build 出的标准 JSON——protobuf 模式（producers 类型化 / consumers 标准化）；
  2. **CLI 黑盒用户**：import/build/check 当独立配置工具（**前提 = D-3 自持校验器**）；
  3. **Schema 书写者**：struct → `jsonmbt schema` → 喂 ajv/VS Code/OpenAPI——schema 四玩家变下游；
  4. **npm/npx 用户**：js 出口打 npm 包，`npx jsonmbt build` 一行进入；
  5. **在线页**：wasm-gc 粘贴→双向预览→下载，零安装。
- **机器生成管道（emitter 直产，importer 之外的第二入口）**：任意语言生成器按五条机械规则直产 .json.mbt（键去引号/值不变/尾逗号可留/字面量原样/头部加 struct+let），类型映射从源语言类型表直查（int→Int/int64→Int64/f64→Double/[]T→Array[T]）。落地三档：① 各语言自拼模板（零依赖）；② **官方 emitter 微包**（jsonmbt-go 先行，label/保留字/转义规则单点实现；其他语言等真实需求）；③ importer 面向存量文件。**已否决 C 库桥**（MoonBit→C→Go cgo 链路每环都比模板拼接贵，且 Go 产 .json.mbt ≈ 产 .json − 引号转义，无需调任何编译器）。
- **Vitro 协同**：第二个 wasm-gc 引擎、诊断方法论第二消费者、demo 互导流；**试点对象 = `diagnostics_data` 人审数据四张**（三张裸 PASS，concepts 加空容器启发后 PASS——真实数据实测可行）；**边界：Rust 冻结档案（2469 张 golden）不转**——档案活在分支上的意义就是不变，改写违背「历史快照不篡改」裁定；「能不能转」（能）与「该不该转」（活数据才转）是两个问题，**纳管判据 = 之后由谁维护**。
- **比赛申报**：名额二候选（独立仓，与 Vitro 非拆分）；如 linter 出山，作为主仓 0.9.0 伴生件。

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

**importer 诊断的人话要求**（非生态用户是主要触发者）：拒绝信息必须可行动——「字段名 `content-type` 非法：连字符不可用于字段名，建议 `content_type`」，不是编译器原文；**「预期校准」话术**：拒绝文案说清「本格式已比浏览器多保真什么、停在哪、为什么」，让用户心智收敛为「jsonmbt ≥ 浏览器，永远」。

## 5. 里程碑（**状态唯一载体**——进度只在此表更新）

| 阶段 | 内容 | 验收锚 | 状态 |
|---|---|---|---|
| P0 探针 | 生态扫描 + moon 四件套行为矩阵 + 类型诊断采样 + parser→JSON 管道 + importer 探针四件（label 矩阵/推断原型/大文件性能/**null→Option·Int64·Map 三映射**）+ 竞品深扫 + **Vitro 真实数据两轮压测（44 张 + 冻结分支 2469 张）** | 管道输出合法 JSON；合成+真实+档案三层数据全测，REJECT 全部落在已实锤逃生门内 | ✅ 2026-10-06 |
| P1 MVP | L0 子集校验 + 降级输出器 + CLI（`build/check`，stdin `-` 约定，**D-10 rc/诊断通道契约**，**D-8 三不变量 + check=build dry-run**，**D-7 单文档基数**）+ **D-3 自持 L0 校验器**（伴生自持 fmt）+ 递归深度防护（参照 Vitro 陷阱 #28 wasm 栈预算探针法）+ 正负样本锚（含 D-9 字符串感知三形态 + 控制字符全族转义） | 端到端 `.json.mbt` → `.json` **按 D-11 规范化器 N 值语义等价**；诊断 ≤1 行 + help；**import→build 往返 N 等价锚**；10+ 样本锚 | 目标 2–3 周（兼职） |
| P1.5 | **importer v1**（形状签名判重 + tagged-enum 识别提示 + D-1 空容器启发 + D-2 Int64 推断落地）+ **`--check` 幂等闸**（flag 包/check 无写副作用/J9 证红）+ **确定性硬锚** + 发 mooncakes 0.2.0 | 确定性锚全绿；check 闸 J9 证红；**Vitro diagnostics 四张试点**（.json.mbt 入仓 + 生成器读降级产物 + Vitro CI 加 `jsonmbt build --check` 步，锁版本） | P1 后 |
| P2 | **npm 包**（js 出口）+ 在线试玩页（**粘贴 JSON 双向框**）+ **`jsonmbt schema` 导出** + **官方 emitter 微包 jsonmbt-go v1** | 双出口同构输出；npx 可跑；schema 经 ajv/VS Code 实测消费；Vitro 生成器直产试点 | P1.5 后 |
| P3 | L1/L2 求值分级 + `&` 去重/展开 + **diff 模式**（语义 diff——CI 基线翻转摘要）+ 键集漂移 Option 缺省（v2 观察项转正评估） | L1/L2 探针锚 + diff 人工验收 | P2 后 |
| P4 生态 | JSON Pointer / json_deriving 联动声明 / 规则手册 / （候选）validate 模式 | — | 远期 |

## 6. 技术决策记录

| 决策 | 裁定 | 依据 |
|---|---|---|
| AST 节点名 | struct 字面量 = `Expr::Record(type_name~, fields~)`；字面量 = `Constant::*` **源文本直传** | parser@0.4.3 mbti 校准 |
| 降级输出后端 | 字符串直拼；浮点文本化对齐 `double_to_json_text` 的 ryu-pretty 规则（禁裸 `Double::to_string`——整值输出 "1"、负零 "0"、中段指数分歧） | 陷阱 #14 + 探针 |
| **数值边界（实测修正）** | **MoonBit Int 是 32 位——真实编译界 2³¹−1，非 2⁵³**；Int64 精确到 2⁶³−1；record 字段位裸大整数字面量合法（无需后缀） | 用户亲测推翻 v0.2 的 2⁵³ 前提；教训：**MoonBit 整数语义不能从 JS/JSON 侧外推** |
| **null 映射** | 字段 `Option[T]`：`null → None`、值 → `Some(v)`——**无损直译**（探针④实锤 Some/None 合法） | 压缩/解压模型的自然推论 |
| **键名逃生门** | 非法 label（保留字/连字符/大写开头）→ 同对象整体 `Map[String, V]`（带引号键 = Map 字面量，探针④实锤；MoonBit Map 插入序=保序直译红利）；降级无引号还原。**适用面写死 = 同值类型对象**；**异值键对象（如 `{"Content-Type":"x","Content-Length":123}`）= 已知不可自动迁移子集**——阻断 issue 列逐字段类型请人工建模 struct（与 D-5 同族：v1 不做 per-key 合并推断） | tagged-enum/HTTP header 类真实数据高频 |
| **D-1 空容器（终案）** | **阻断 issue + 可行动诊断 + 同形复用启发**（同文件内同名/同形字段他处非空 → 复用其元素类型，规则写死进锚；孤立空容器才提问；空对象无元素可抄、单独形态诊断）。**否决**字段省略+头注登记（违反无损与全有或全无）与 Json 类型逃逸（破 L0 纯度、病毒扩散） | 用户裁定；Vitro concepts.json 40% 空数组实证启发为主路径特性 |
| **D-2 大数（终案）** | **默认 Int64 推断**（值超 Int 全体上浮）；**跨样本无损方向归一**（同字段任一样本超 Int → 全体 Int64）；**超 Int64 诚实拒绝，不静默 Double 化**；**不采纳字段注解**（`#json_bigint` 触发 unused_attribute 黄牌，毁 check 干净卖点）；**字符串化 = 显式 opt-in**（保精度≠转字符串，两件事拆开） | 用户裁定；「默认字符串化」是 v0.2 设计陷阱（`{"id":123}` 变 `{"id":"123"}` 类型变了、往返不再无损） |
| **D-3 自持校验器** | `jsonmbt check` 内嵌 L0 校验器（几百行）+ `--moon-check` 可选深验；**按 mini-tsc 预期写**（L1/L2 落地时跟着长，moon 工具链万一不管用时已是独立类型检查器） | 非生态用户采用前提 |
| **D-4 跨文件引用** | 不做，单文件自持 | 试点数据 780 行内自持无压力 |
| **防线双层** | 内层 moon test 语义锚（随工具链漂移但漂移即编译红）+ **外层 Go 黑盒驱动 = 对外承诺的真防线**（CLI 进程契约/rc/stdout 字节/往返链/确定性/压测——只依赖 exe） | 脚本测试先满足稳定性（用户裁定）：moon test 计时与依赖随工具链漂移；外部调用走进程边界必须在进程层测（Vitro 硬防线全为 Go 黑盒的同构理由） |
| **脚本选型** | 层 2 驱动用 **Go**：五约束交集（独立于 moon/进程编排/零运行时依赖/兼职可维护/复用 Vitro 资产——smoke 驱动·exe 新鲜度门禁·golden 管理直接抄）；Rust/Python 逆版图裁定（刚退役），Node/TS 用漂移源测漂移源，shell 断言力不足，MoonBit 写 driver 过漂移工具链 | 版图一致：Go 本就是「驱动/归一化器」门 |
| importer 推断 | 形状签名判重；同构数组 `Array[T]`；阻断 issue 全有或全无；tagged-enum（`{Void:true}`）识别提示建模 enum；**字符串值疑似嵌套 JSON（JSON-in-JSON 双层形态）提示**（冻结分支 codegen golden 实测发现的观察项） | 探针 10 样本 + 4 原型 bug 预演 + 2469 压测 |
| CLI 动词面 | 对齐 CUE：`build`/`check`/`fmt`/`import`/`schema`/`diff` | 心智零迁移 |
| 命名 | 格式 `.json.mbt`（品牌不变量）/ 包+仓 `rustin-beep/jsonmbt` / CLI `jsonmbt` | owner=产品名重合产生定位噪音 |
| 竞品边界 | gmlewis = 先驱非威胁；schema 四玩家 = 下游；moonjson = "读"；jsonmbt = "写 + 类型 + 工具链 + 闭环"。README 主动声明共存 | 探针扫描 + 先例矩阵 |

## 7. 风险登记表

| # | 风险 | 概率 | 对冲 |
|---|---|---|---|
| R1 | moon 工具链 breaking 影响 .json.mbt 行为 | 中 | 探针行为矩阵固化为测试锚（P1 起）；moonbit 升级手册同款流程 |
| **R1b** | **依赖 moonbitlang/parser 的非公开 AST 面**（`@syntax.Expr` 等无兼容承诺——比「工具链一般性变化」更具体更危险） | 中-高 | AST 节点快照测试 + 锁 parser 版本（现锚 0.4.3）+ 每次升级跑行为矩阵；升级红 = 按 AST diff 逐节点定责 |
| R2 | 求值分级被"加功能"诱惑突破 | 中（自律） | 分级冻结条款 + 逃生门原则（表达不了的写 MoonBit 去）；Jsonnet 蔓延史佐证；Vitro 诉求分流（语言面分级评审、工具面自由加，自家消费不跳级） |
| R3 | 大数/转义边角坑 | 高 | 每项进负样本锚；D-2 终案已裁 |
| R4 | 采用率：用户为何弃 JSON5/JSONC | 存在 | fmt+check+确定性三件套；**satisfies 模式流行度证需求真实**；MoonBit 生态内首发卡位；importer 拆迁移成本。**量化基线（诚实数字）**：冻结分支实测裸 PASS 49%、Vitro 活数据 43%——**采用摩擦约一半是真实的**；对冲 = 三逃生门落地（预期裸 PASS ≈100%）+ JSONC 输入；**P1.5 验收重测两数字，逃生门落地后裸 PASS 仍 <80% 则 R4 升级高危重估定位** |
| R5 | 官方未来内建 typed-json | 低-中 | 规范与 MoonBit 类型系统深度绑定；即便内建，CLI diff 工具链仍是独立价值 |
| R6 | 键名合法性天花板（kebab-case/保留字/大写开头） | 高 | Map 逃生门 + 拒绝清单给可行动改名建议；实测：camelCase/snake_case 主流全兼容 + 中文键合法 |
| **性能已除名** | 551KB 实测全链 <1.1s（infer 0.03 + fmt 0.29 爆 10888 行 + check 0.74，0 errors）；9 struct/274KB 产物；**「大字面量与 fmt 互踩」的 Vitro 教训不适用于 record 形态** | — | — |

**压缩比实测（双口径）**：大文件 vs pretty JSON = 0.61×（564KB→341KB）、vs 紧凑 JSON = 1.26×、gzip 后 1.05×（传输无差异）；**行数口径（人眼维度）**：大文件 32,990 行 → 10,888 行 = **0.33×**（滚动量降 2/3，fmt 按 84 字节行宽打包 vs JSON 每标量一行的缩进噪音）；小文件多付 6–12 行类型头，换来值体单行内联 + 类型头即 schema 文档。定位语：**「YAML/TOML 是给人读的配置；JSON 是给机器读的数据；.json.mbt 是给机器读的数据的『人写形态』」**。

## 8. 规范决策点

| # | 决策点 | 裁定 | 状态 |
|---|---|---|---|
| D-1 | 空容器语义 | 阻断 issue + 同形复用启发（规则写死进锚）；否决省略登记与类型逃逸 | ✅ 终案 |
| D-2 | 大数策略 | Int64 默认推断 + 无损归一 + 超 Int64 拒绝；注解不采纳；字符串化 opt-in | ✅ 终案 |
| D-3 | 自持校验器 | 0.1.0 范围 + mini-tsc 预期 | ✅ 终案 |
| D-4 | 跨文件引用 | 不做，单文件自持 | ✅ 终案 |
| D-5 | 空数组/键集漂移的 Option 缺省（缺失字段按 Option 推断） | v1 先拒（「拼错字段名」与「真可选」无法区分，静默错值风险）；v2 观察项。**转正触发条件**：试点满 1 个月 +「因缺字段可选性被阻的 import 次数」≥N；**转正形态必须逐字段显式标注，禁止全局默认** | 挂起（触发条件已定） |
| D-6 | Go 直产 emitter | 微包三档（自拼/官方库/importer），C 库桥否决。**双实现面约束：emitter 与 MoonBit 降级器受同一份 golden 往返用例约束**（同输入 → emitter 产 .json.mbt → build 降级 → 与原 JSON 值语义等价——往返锚即双实现对账锚） | ✅ 终案 |
| **D-7** | **文件→JSON 基数** | **一个 `.json.mbt` = 恰好一个顶层 `pub let`**（单文档语义；`pub` 消除 unused 警告守 check 干净）；**命名取文件 stem**（`config.json.mbt` → `pub let config`——天然避同包顶层名冲突）；**多于一个 `pub let` = 诊断错**（歧义文档）；其余 `let` = 文件内部绑定（**L2 落位由此锁死**，未来不改基数定义） | ✅ 终案 |
| **D-8** | **build 三条不变量** | ① **校验先行，失败零产物**（含不覆盖已存在 .json）；② **非 L0 节点 fail loud**——删除原型 `_ => "null"` 兜底，遇函数调用/算术/条件即诊断中止；③ **产物原子写**（临时文件 + rename），失败不留半截产物。**`--check` 必须复用 build 的同一条校验路径**（check = build 的 dry-run——两套校验语义必漂移，Vitro 生成器 -check 契约同款纪律） | ✅ 终案 |
| **D-9** | **importer 输入源集合** | v1 = **JSON + JSONC**（注释剥离须字符串字面量感知 tokenizer，约半天——裸正则必误伤 `"http://x"`/`"a//b"`；负样本锚必含这三形态）；JSON5 留 v2。**输入按内容探测**（非扩展名）；**剥离加字节确定性锚**（同输入剥离结果恒定） | ✅ 终案 |
| **D-10** | **CLI 契约（rc + 诊断通道）** | **rc 五值表（与 Vitro CLI_PROTOCOL_V1 家族对齐 + 有义分叉）**：0 成功 / 1 输入错（校验/类型错） / **2 检测到漂移或差异**（--check 红、diff 有异——Vitro 2=trap 本仓无 trap，**有义占用须登记分叉**，借鉴 terraform detailed-exitcode）/ 3 保留 / 4 用法·IO 错。**纪律：rc 与标记行前缀只增不改**。**诊断通道 = stderr**（Vitro stdout 被程序输出占据故标记行走 stdout；本仓产物写文件、无程序输出），定义机器可读前缀 `jsonmbt: error [J3004] path:line:col …` + `--json` 结构化模式 | ✅ 终案 |
| **D-11** | **往返锚定义（值语义规范化）** | **`N(build(import(J))) == N(J)`**——「逐字节等价」结构上不成立（实测：JSON 合法的 `1e2` **写不成 MoonBit 字面量**——纯整数尾数接指数被拆成 `1`+标识符解析错，陷阱 #13 勘误：指数记法必须带小数点 `1.0e2` 合法）。**规范化器 N 钉死**：① 数值——整数走 Int 十进制文本；含 `.`/`e` 走 Double→`double_to_json_text`（ryu-pretty，**禁裸 to_string**，复用 Vitro ast 单源不重写）；指数记法一律展开十进制规范形；② Int/Double 按源文本是否含 `.`/`e` 判型（`1`≠`1.0` 保留）；③ 字符串按解码后码点比较，输出侧统一转义（控制字符 `\u00XX`，对齐陷阱 #27）；④ 键序=源序不排序；⑤ null→None→null、空容器按 D-1。**登记不可逐字节已知面**：整数尾数指数（`1e2`）/ >Int64 / 超 17 位有效数字浮点 / **重复键=拒绝**（JSON 层重复键是病态输入，importer 不替它选语义——对齐「重复键结构性不可能」卖点） | ✅ 终案 |

## 9. 探针存档（证据链）

- **探针①label 合法性**：合法 = snake_case/驼峰（小写开头）/下划线开头/单字符/**中文键直接合法**；非法 = 大写开头（IDE 级报错）/字符串 label（语法不存在）/保留字（type/match/loop/case 实测）
- **探针②③推断原型**：10 样本 = 4 生成 0 errors + 6 诚实拒绝；形状签名判重 + 4 原型 bug 预演（签名判重/空对象假类型/定义不收逗号/嵌套值须递归渲染）
- **探针④三映射**：`Some(v)`/`None` 合法（null→Option）；record 字段位裸 Int64 字面量合法（无后缀）；带引号键 Map 字面量合法（键名逃生门）
- **大文件性能**：551KB 全链 <1.1s——性能除名
- **探针⑥数字字面量（D-11 决定性）**：`1e2`（纯整数尾数接指数）**解析错**——被拆成 `1`+标识符；`1.5e3`/`100.0`/`1.0e2` 合法——**指数记法必须带小数点**；16 位整数字面量 Int64 位合法 / Int 位 out of range（再证 D-2 的 2³¹−1 界）。**陷阱 #13 勘误**：原文「e 记法浮点字面量不可用——写定点」不准，实情是「纯整数尾数不行，须带小数点」。**附带新陷阱 #42**：新工具链（rr_moon_mod 特性）下 `moon.mod.json`/JSON 式 `moon.pkg` 解析失败，必须 `moon.mod` + 块式 `moon.pkg`
- **Vitro 真实数据两轮**：现行仓 44 张 = 19 裸 PASS / 25 REJECT（非法键 39 处·空容器 22·异构 12·动态键文件名/诊断码约 15 张属 A 类不迁）；**冻结分支 2469 张 48.1MB = 49% 裸 PASS，REJECT 100% 落在 tagged-enum/空容器/动态键三门内，零未知形态**——importer 迄今最大规模实战验证
- **探针产物**：`D:\code\jsonmbt_probe\notes\`（label 件 + 4 生成件 + 大文件产物）——临时环境，P1 起样本迁入本仓 `probe/`，外部路径视为已失效
- 竞品与先例：§2 矩阵

## 10. 边界声明

jsonmbt 是通用开发工具，**不是教学产品**。`.json` 仍是机读标准形态，`.json.mbt` 只服务"人写 JSON"的场景。

**维持不做（有实锤理由）**：JSONC 输出带注释（破坏确定性）、多文件 include（D-4）、环境变体 CLI 糖、VS Code 专属插件（官方 LSP 覆盖）、字符串集合自动推断 enum（阈值判定破坏推断确定性——v2 观察项）、**JSONC 同类弱格式**（自建工具链=Dhall 死因，importer 输入支持即可）、**C 库桥**（D-6 否决）、**Rust 冻结档案转换**（档案不转——活在分支上的意义就是不变）。

**文档/实现比纪律（R10）**：v0.3.1（~24KB 规范）与实现（探针 68 行）的差距必须在 **P1 验收时清零**——每条 D 系裁定至少落一个测试锚，否则规范降级为草稿。规范先行是 P0 阶段的正常形态，纸面化不是。

**观察项转正制度**：全部观察项（字符串推断 enum / JSON-in-JSON 提示 / JSON Pointer / validate 模式 / D-5）必须带**转正触发条件**（信号 + 阈值 + 转正形态约束），无触发条件的观察项不予登记——防僵尸。
