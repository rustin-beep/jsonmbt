# Changelog

本仓全部可见变更记录。格式与纪律见 [AGENTS.md](AGENTS.md) 纪律 6。

## [Unreleased]

### Added（issue #26：emitter 对含 `\n` 字符串产 `#|` 多行——教师循环形态保真，方案 1）

- **动机**：`#|` 手写真源（43 条长中文）→ build 降级 → 改值 → `--fill` 回写——全部条目（含未变的）磨损成单行转义长串，写作面单向退化；`#|` 多行是手写面核心可读性卖点，回写必须保形
- **落法（方案 1，工具面）**：`render_string_value`——值含 `\n` 产 `(\n#|行\n…)` 值位括号包裹 + **无前导空格规范形**（moon 语义 `#| x` 空格入值，不产即不引入——与 #24 语义对齐）；单行值保持转义；**含 `\r` 的值例外走转义单行**（CRLF 行尾 `\r` 入值语义在读取层有歧面，转义保真）
- **探针先行（fmt 幂等形态）**：构造器 payload/record 字段/Map 值/数组元素/Some 内全值位 moon 合法；fmt 归一为「值位括号包裹 + `#|` 随嵌套缩进」，二次 fmt 不动——emitter 产顶格 `#|`，fmt 一跑归一、幂等（#25 的 Group(Paren) 恰好铺平 `#|`×括号×fmt 共存）
- **教师循环端到端实证**：`#|` 真源 → build → 改一条值 → `--fill` 回写——未变条目 `#|` 原样存活、改值条目产 `#|` 多行（不再磨损）；方案 2（增量保形）的动机随形态恢复消失，不做
- **锚**：层 1 红→绿（含 `\n` 产 `#|` + 单行保持 + 回吃往返无损 + `\r` 例外）+ 埋雷证红（临时还原旧 escape 分支 → `#|` 形态断言红）；JSON 输入的 `\n` 转义在 moon 源码层用 `\u{5c}n` 构造（heredoc 产不出 `\\n`——环境坑又实锤一次，锚写法对齐 D-9 三形态锚先例）
- **文档三面**：demo 矩阵——「JSONC 注释剥离」条目勘误（「JSON 输入侧不吃尾逗号」已过时→尾逗号/BOM 全收）+ `#|` 条目补回写保形 + 新「冗余圆括号剥除」条目（#25 顺带补齐 demo 面）；skill——规则 5 补 emitter 规范形 + `--fill` 工作流补「教师循环形态保真」段 + emitter 纪律新增第 4 条；README importer 段补一句
- 门禁：层 1 **118/118**、层 2 **32/32**（双 exe）、pages smoke ALL OK（demo 矩阵更新后 31 断言全绿）

### Fixed（深度审阅处置 2026-10-10：P1×3 修 + P3×2 修——审阅探针/突变注入双验）

- **P1-a `lub` 缺 `JTOption` 臂**：`#20` 元素位自聚合后 JTOption 首次流入 lub，旧匹配表落 hetero——`[{"a":[null,1]},{"a":[null,2]}]` 报 `Int? vs Int?` **同型误拒**（旧实现靠 `(JTNullLike,t)` 静默吞掉的空洞被 #20 暴露）；补 Option 双向臂（内层递归 lub——同型保型/上浮语义不变，null 由 NullLike 臂先行兜底）；双样本锚 + 真异构仍拒负锚
- **P1-b `unescape` 花括号路径缺代理检查**：`\u{d800}` 只查 >0x10FFFF 上限——代理点 `unsafe_to_char` 后降级链 panic 且 **check 放行 build 崩**（绕过 D-8 ① 校验先行）；moon 本尊 `[4064]` 拒（审阅实测）——jsonmbt 不比 moon 严；花括号分支补定长 `\uXXXX` 同款代理区检查 → J3003（#16 同族逐处对齐）；锚含 0x10FFFF 合法收码点断言
- **P1-c `--fill` 标量 payload 空键 panic**：`{"case":"Scalar"}`（无 value 键）对声明 `Scalar(Int)` 在 `render_variant_payload` 取 `payload_keys[0]` 越界 panic；改 J3006 fail loud（fill 只重写值体——数据与声明不同步不吞错）；#14-2b 新代码的可达性空洞
- **P3 `--strict` 误用守卫**：build/check 带 `--strict` 曾静默忽略（与同批 `--input` 自立的 fail-loud 纪律相悖）——补 JUsage（strict 是推断档，build/check 无推断面）；层 2 `jsonc-input-profile` 补断言
- **P3（文档）CHANGELOG 增量链自洽**：#22 段 `+7` 勘误为净 +6（P2-6① 迁移是重写非新增——链条 104+2+6+2=114 对账）
- 门禁：层 1 **117/117**（+3 锚）、层 2 **32/32**（双 exe）、四件终 exe 手验（P1-b check 侧先拒 = D-8 ① 恢复）

### Fixed（issue #25：L0 拒绝冗余圆括号包裹的字面量——moon fmt 规范产物可读）

- **定性**：`A(("x"))` 是合法 MoonBit（fmt 幂等保留该形态——实测复核：payload 构造器位保留双括号、数组位收敛单层），值上严格等价 `A("x")`——拒绝即「合法 MoonBit 子集」承诺的非预期收窄（与 #16 转义宽集同族：jsonmbt 不比 moon 严），互操作 bug 级（真源进 fmt 跑的 workspace 即触发，Vitro #60 批一实录）
- **修法**：`l0_expr` 新增 `Group` 分支——`Group(Paren)` 递归剥除（多层括号自然解、depth+1 计入防括号炸弹）、`Group(Brace)`（花括号块 = 副作用序列面）仍 J3001 拒（负锚：`A({ let s = "a" s })` 合法 MoonBit 但拒）；分发层修复 = **所有值位统一剥**（payload/数组元素/record 字段/Map 值/Some 内），不止 issue 建议的 payload/数组两处
- **AST 快照登记**：`ast_snapshot_wbtest` 投影加 `G(p/b, …)` 变体 + 快照样本括号字段（parser 升级对冲面补齐）
- **锚**：层 1 红→绿（`A(("double"))`/`A((#| 多行))`/三层括号值等价 + Brace 负锚）；probe/samples 新样本 `paren_payload`（fmt 后单层括号形态 + `#|` 带空格，moon check 干净——首版 enum 形态触发 `unused_constructor` warning 改自由数组，payload 位防线在层 1 锚）
- 层 1 **114/114**（+2）、层 2 **32/32**（probe-samples 自动消费新样本）、build 0 err

### Added（issue #22：JSONC 尾逗号收编——消解式，D-9 重写为输入 profile 单点定义）

- **判据（可判定非枚举）**：只收「字符层删/替空白可消解为严格 JSON」的宽松特性——注释、对象/数组/嵌套尾逗号、BOM（仅文件首）收；`{,}`/`[,]`/`[1,,]`/`{"a":,}`、单引号串、无引号 key、hex、`NaN`/`Infinity` 永不收（扩值域——JSON5 因此不进）；tsconfig/eslintrc/settings.json 类真实文件直接进
- **落法 = 消解式**：`strip_jsonc` 从注释剥离器升级**输入归一化器**（唯一宽松层），尾逗号同一 pre-pass **等长空格消解**（诊断行列不漂移）；`jsonparse.mbt` 恒裸 RFC 8259——对拍基准不污染（parser 仅删两处 `(trailing comma is not JSON)` 括号注释：消解式下不可达，防误导）
- **机制**：pending-comma 暂存（穿透空白**与注释**看有效字符才判定）+ last_sig guard（逗号前一非空白有效字符 ∈ `{ [ , :` 或文件首则不消解）+ BOM 仅 `pos==0`；埋雷实锤 guard 的真实价值 = 报错位正确性（禁用时报错从 U+002C 漂到 U+005D——「保位」锚先红）
- **CLI `--input <json|jsonc>`**：默认 jsonc；json = 裸 RFC 8259（注释也拒）；import/fill/migrate 三入口同旗标；别值 J0001、非 import/migrate verb 误用拒绝；**不复用 `--strict`**（#14-2a 已占用）；库层 `import_source`/`fill_source` 新增 `jsonc? : Bool = true` 出口面参数（mbti 已同步）
- **锚拆档（防线净增）**：P2-6① 原断言迁移至 json 档锚（永久保留——重写非新增）+ 默认档翻转为值等价锚；负锚五形态（开头/孤立/值缺失逗号）；BOM 锚（文件首消解 + 字符串内 U+FEFF 保留）；穿透注释锚；保位列位锚；层 1 **112/112**（净 +6 = 五新锚 + manual 摄取章可执行锚；审 P3 勘误：原记 +7 误将 P2-6① 重写作新增——增量链 104+2(#24)+6(#22)+2(#25)=114 自洽）
- **层 2 第五件**：probe/samples 新样本对 `tsconfig_like`（.jsonc 三合一输入 + 人写语义命名 .json.mbt + golden .json）；caseProbeSamples 扩第二循环（.jsonc 输入 → import → build 与 golden 比 + `--input json` 同输入必拒）；新用例 `jsonc-input-profile`（旗标值域/误用/双档对拍）——层 2 **32/32**

### Added（issue #24：Vitro 教学资产批实战反馈——建模指引 + `#|` 空格语义 + doctor 排版 note）

- **键域强校验指引三处落文**（#24-1）：manual 新可执行锚「键域强校验——带参枚举数组」（`Map[AlgoE, String]` 裸构造器键位 moon 本尊即 `[4014]` 拒——语言层边界，本仓探针复核；正解 = 带参枚举数组，降级 `[{"case","value"}]`）+ skill 规则 3a + README importer 段——Vitro 两轮探针摸出来的路，写下来免重摸
- **`#|` 前导空格语义文档化**（#24-2）：moon 原生语义 `#| x` 值 = `" x"`（非 jsonmbt 偏差）——manual 新可执行锚 + skill 规则 5 补句
- **doctor 排版 note**（#24-2b）：「全部非空 `#|` 行统一前导空格」形态 → note 行（hint 级——不计 ❌/⚠️、不改 rc：接线闸不掺内容口味；空行/纯空格行不参与统计，缩进 `#|` 不参与——moon 标记顶格，漏报无害）；层 2 新锚 `doctor-pipe-hint`（红→绿：实装前证红 + 对照组无 note 断言）
- 层 1 **106/106**（manual +2 可执行锚）、层 2 **31/31**（+1 用例）

### Fixed（issue #23：build 无 -o 默认输出名护栏 + 落盘 hint 点名输出路径）

- **主诉求在 HEAD 不复现**（三重证据：`main.mbt` 唯一 `.json` 拼接点自 P1 MVP 未变；import/migrate 三条输出路径全排查无坑形态；Vitro 原文件 `rules.json.mbt` 原名实测产出 `rules.json` 正确）——issue 实录的 `.json.json` 最可能源于 Vitro 滚动消费本仓 `_build` exe 时的旧/中间态产物（陷阱 #41 下游版）。处置 = 锚死契约 + 补建议 2，不改动正确行为
- **层 2 新锚 `default-output-name`**：单/多输入 `x.json.mbt` 无 `-o` → 断言 `x.json` 存在且 `x.json.json` 不存在（issue 实录老坑形态点名拦截）+ 产物内容正确；埋雷证红（临时注入剥 `.mbt` 坑形态 → 5 用例红，含本锚）后排雷全绿
- **落盘 hint 点名实际输出路径**（issue 建议 2）：`build without --pretty emits compact JSON → '<target>'`——下游批量脚本漏 `-o` 时 hint 只说形态不说去向帮不上忙；带 `--pretty` 静默、`-o -` 无落盘 hint 契约不变
- 层 2 30/30（+1 用例）；层 1 104/104、build 0 err（无涉改动，回归确认）

### Added（issue #19：Map 键序契约进下游文档）

- INTEGRATION.md 新节「机器生成 .json.mbt（emitter 作者契约）」：Map 键序 = 源文本序（不排序——D-11 ④）、禁止依赖运行时 map 遍历序（Go range 序随机——Vitro jmemit 实测踩坑）、任意确定性序皆可；README 契约清单同步一行。行为无变化（契约一直在，本次补文档面——锚早已在位：probe/samples Map golden 锁键序 + PLAN D-11 ④ + skill emitter 纪律 2）

### Added（issue #17：数字降级规范化契约成文——方案 C）

- README 契约段 + 层 1 专用锚：整数族（Int/Int64）解析值归一（`-0`→`0`、`0x10`→`16`、Int64 全精度文本保留）；Double 源拼写透传（`1.50` 原样——避免解析-再格式化精度伪影）。方案 B（规范化为最短往返）被否：破坏透传的无损设计且收益仅限「人工改拼写」场景（机器生成源天然稳定）。层 1 97/97

### Fixed（issue #16：字符串转义宽集对齐 moon 词法）

- `unescape_string` 补三形态：`\/`（JSON 惯用，moon 实测接受）；`\uXXXX` 定长（moon 词法宽于文档——rc=0 接受，「MoonBit 接受 ⇒ 必须接受」）；**代理对合成**（`\ud83d\ude80` → 🚀，UTF-16 语义）；**孤立代理拒收**（J3003）
- 勘误（逐项实测）：#16 主表 7 项中 5 项（`\t \n \" \\` 等）在最新 exe 已工作（审计为 10-07 旧版）；「import 含转义 JSON 全灭」推测不成立——JSON 侧解析器一直支持 RFC 8259 全转义集
- README 转义契约成文（输入侧 = moon 词法宽集；输出侧 = 最小转义 + 非 ASCII 裸 UTF-8，同值异形输入产同一规范形）
- 层 1 两锚（宽集对齐 + import 往返值等价与规范形）→ 96/96；probe/samples 新样本对 `escapes`（全转义族，moon check 同源双验）；层 2 26/26

### Added（issue #14 批次 2b：`--fill` 按已声明类型重算值体 + 分档闸）

- `import x.json --fill x.json.mbt`——第三条注记通道（类型定义本身）落地：读已有产物的类型头（analyze：structs/enums/field-alias 注记全收），**以声明类型驱动渲染源 JSON 值体**——空容器直吃声明元素类型（不再 Never/启发）、键集漂移按声明 enum 消歧（`case` tag 键或键集精确匹配双形态——fill 能吃自身降级产物，round-trip 闭环）；无匹配变体 J3004、键集多余/缺失 J3005/J3006（数据不同步不吞错）
- **头逐字节保留**：切分点 = `pub let` 行内首个 ` = `（注解属类型头）——人工改名、新增 struct、手写注释全部存活（层 2 断言）
- `--fill --check` **分档幂等闸**：头保留语境下校验值体与源 JSON 同步（源变 rc 2 J5001）——不再惩罚人工语义命名（与 `--type-name-map` 双通道共存）
- `-o -` 预览；`--type-name-map`/`--strict` 与 fill 互斥（语义不交集，J0001 fail loud）
- 渲染器 `strict_keys` 参数化（一套双模式，import 主路径零变化）；`fill_source` 出口（moon info 登记）
- 层 1 94/94（fill 三用例：直填/消歧双形态/负样本）、层 2 26/26（fill 用例：头保留/同步 rc0/源变 rc2/预览/互斥）

### Added（issue #14 批次 1+2a：T?? 收窄 + 空容器 Never 占位）

- **T?? 递归收窄 J2007**（批次 1）：实测 `String??` 下 `None` 与 `Some(None)` 降级都成 `"a":null`——静默压平违反 §0 无损与 D-8 ②；`scan_supported_type` 嵌套 Option 分支 fail loud（任意深度递归拒，J2007 专属文案指向三态评审状态）。推断链只加一层 Option——**纯手写面，现存绿文件零影响**（层 1 三形态锚 + 层 2 golden 双证）。三态展平式（None=缺席/Some(None)=null/值）走 §8 评审；容器位（Map 值/数组元素）结构上无法缺席，评审落地前一并收窄
- **空容器 Never 底型占位（默认）**（批次 2a）：J4001/J4002 不再整张拒——`exemptions : Array[Never]` / `cfg : Map[String, Never]`，产物含 `pub enum Never {}`（fmt 归一形态，探针实锚）；**一条机制同解空数组+空对象**（零信息容器的数学精确刻画——非猜测占位，输出逐字节不变）；**免费护栏**：元素位写值被 moon `[4014]` 与 jsonmbt J3004 双侧拦下；D-1 两级启发优先级保持（能推精确类型的绝不出 Never，收尾统一占位只兜真孤立）
- **`--strict` 反向 opt-in**（严格档=旧行为）：空容器启发无解时如旧 J4001/J4002 拒（J4001/J4002 语义收窄到 strict 档——旧锚已迁移 strict 形态）
- **J4031**（新码，rc 0）：占位 hint——非空样本出现后换真类型（或 re-import）
- **Never 预留**：`used_type_names` 初始含 Never——`{"items":[{"never":1}]}` 派生组名被迫去重 Never2，底型名不被占用
- probe/samples 新样本对 `empty_containers`（fmt-stable + moon check 编译面 + golden 往返）；层 1 91/91（+2 用例，3 旧锚迁移）、层 2 25/25（+1 用例）

### Fixed（深度审阅处置：P1×1 + P2×2 + P3×3 修 / P3×1 拍板登记）

- **P1 部署门不挡红**：`pages/smoke.mjs` 断言失败只有 `console.log`、rc 恒 0——`pages.yml`「smoke 红不上线」承诺不成立。修：末尾 `if (bad) process.exit(1)` + 头注从「一次性勘探勿入防线」改为部署门口径（注入复现双向验证：坏断言 rc=1 / 正常 rc=0）
- **P2 嵌套 enum payload 误报**：`enum Field { Named(Col) }` + 字面量 `Named(X)` 被误报 J3004——payload 形参类型存 parse_type 原值（JTStruct 裸名），payload_case 消费点漏 `resolve_custom`（root/struct 字段侧都 resolve，唯 payload 漏）。修：消费点 resolve；层 1 新用例先行红（审阅注入证明锚聋——修复后 87→88 锚仍绿说明原 87 无此路径）
- **P2 migrate taken 模拟失真**：目录已有 .json.mbt 孪生时 taken=[] 起始漏盘面名——`--write` 产物与真实 import 不一致 → `import --check` rc=2 自相矛盾。修：per-directory 预扫盘面既有 .mbt struct 名作起始 taken + 目录级累积（跨目录互不影响，对齐真实 import 的输出目录扫描基准）；层 2 新用例（前缀化告警 + 自洽闸 rc=0 + BId 形态）先行红
- **P3 J4010/J4011 截断计数**：诊断在首个冲突合并处短路，后续样本未入分布——「N distinct in M samples」实为下界。修：help 明示「counts cover samples seen up to the first conflicting merge — treat them as lower bounds」（层 2 golden 先行红同步）
- **P3 pages.yml 缺 MOON_CC**：与其自身注释/index.html 页脚「同款命令勿单侧漂移」矛盾——补 `env: MOON_CC: clang`（js 后端实际不走 C 编译器，仅为三处命令形态一致）
- **P3 矩阵与 smoke 不同步**：index.html Option 卡 `Some("x")` vs smoke `None`——smoke 改为 index 卡逐字同步 + None→null 语义专断另立一条（BUILD 集 4→5，「全部过冒烟」承诺成立）
- **P3 payload `value` 键不对称（拍板：登记不修）**：标量 payload 用 `"value"` 键、struct payload 含 `value` 字段展平同键——J3008 只防 `case` 不防 `value`。拦 `value` 会误伤合法数据字段（真实成本）vs 实际歧义可由 `case` 值区分（收益低）——登记为 D-5 已知面（PLAN §6）
- 审阅「已排除」两项（cmp_rows `×` 偏移未致排序失效、`#|` 行不误触注记扫描）确认不处置

### Fixed（issue #15：J2007 help 文案与实现对齐）

- J2007/J4003/J3004/J3006 四处 help 文案的 `Option[T]` → `T? (Option)`——Option 的合法写法是 MoonBit 后缀糖 `T?`（前缀形态 `Option[Int]` 被 parse 判 JTUnsupported 拒收），文案列 `Option[T]` 为 supported 是指路被拒写法（pages playground 样例卡实测发现）。方案 A（改文案）；方案 B（放开前缀别名）按 issue 论证不做（引出产物 fmt 形态问题）
- 层 1 两处逐字节锚先行红（negative_test 115/208）→ 绿 87/87；层 2 新增 `j2007-help-text` stderr 逐字节 golden，23/23 绿

### Added（pages 体验：加载等待提示 + README 直入标签）

- `pages/index.html`：引擎改**动态 `import()`**——静态 import 会把整个交互脚本卡在 ffi.js（~7.8MB）下载期（输入框可见但零反馈）；现先绑 UI 并显示「⏳ 引擎加载中」状态（新 `#status.loading` 样式），就绪后自动跑初始转换，失败显式报错（网络/GitHub Pages 分发问题可诊断）；下载期间的手动转换提示「将在就绪后自动执行」
- README 顶部（banner 下）加**在线试玩直入标签**：<https://rustin-beep.github.io/jsonmbt/>
- 验证：页面 module 脚本 `node --check` 语法过；动态导入链 node 实跑（import→build 往返）绿；smoke 22 断言复跑绿

### Added（issue #6-5：`jsonmbt migrate` 批量迁移侦察三榜报告）

- `jsonmbt migrate [dir] [--write]`——把「探测哪些能迁」从下游仓手写 shell 脚本产品化：逐张 import → build（pretty+compact）→ 与原文件比对三榜：**BYTE-EQ**（行尾归一逐字节相等，可直进 CI 对账）/ **VALUE-EQ**（值语义等价键序不敏感——新 `@src.json_value_eq` 树比；风格差，接 CI 前须确认字节口径，报告尾 hint）/ **REJECT**（J 码 + 消息首行）；DIFF 兜底榜（往返值不等理论不可达——出现即缺陷信号）
- **默认零写**（侦察契约）；`--write` 落盘非 reject 产物；rc：任一 reject/diff → 1（迁移完成度闸）
- **内存 taken 累积**模拟「逐张真实迁移」的同目录撞名序列（#4 前缀化复现）；前缀名出现时 note 行指路 `--type-name-map`
- 已有同名 `.json.mbt` 孪生的文件跳过（已迁移不重复报）；JSONC 原文件因注释恒落 VALUE-EQ（如设计）
- 层 2 +1 用例（三榜分类/零写/--write/rc/空目录），22/22 绿

### Added（issue #6-4：`--type-name-map` + Map 值宿主派生命名）

- `import --type-name-map <map.json>`：机器派生名（Id/File2/Print_int 等零信息量形态）→ 语义名映射；**键 = 最终派生名**（用户从首次 import 产物复制——含 #4 跨文件前缀化形态如 ItemsId）；值校验 fail loud（非法类型名/撞已占类型 → **J1010** 新码；映射文件坏 JSON → J1002、形态非对象/值非串 → J1010）；未命中键 → hint 不阻断（typo 核对提示）；build/check 误用该 flag → JUsage
- **Map 值类型命名改宿主字段派生**（issue 评论拍板）：`cases : Map[String, Src_sha]`（首键派生，值实为完整条目——误导）→ `Map[String, CasesEntry]`（Map 持有者名字为语义锚）；数组位/顶层无宿主 → fallback 首键派生；首见定型，确定性保持
- `ImportOutcome` 增 `unmatched` 出口（层 1 锚）；层 2 +1 用例（映射全链/J1010×2/hint/宿主派生），21/21 绿

### Added（pages CI 接线：GitHub Pages 自动部署）

- `.github/workflows/pages.yml`：push master / PR / 手动触发——js 引擎构建（debug，release tree-shake 坑已登记）→ **22 断言 smoke 作部署门**（断言红不上线）→ index.html + ffi.js 上传 → `deploy-pages` 发布；PR 只验不部署
- Pages 站点经 API 启用（`build_type=workflow`）：<https://rustin-beep.github.io/jsonmbt/>（HTTPS 强制；index.html ESM 相对路径天然兼容项目子路径）
- index.html 页脚更新为 CI 自动部署说明

### Added（issue #5：`jsonmbt doctor` 只读接入诊断）

- `jsonmbt doctor [dir]`——诊断「这个仓的 .json.mbt 有没有真正接上 MoonBit 工具链」（Vitro 批②最大坑：不在包边界内的文件 moon 完全看不见，「验证了没被编译的东西等于没验证」）。**只诊断不 setup**（包怎么切/workspace 怎么分是用户仓的结构决策）
- 每文件四项：包边界（moon.pkg 在本目录 + 祖先链模块根；❌ 给一行修复）/ 跨文件 struct·enum 撞名（moon 编译期才炸的坑提前拦）/ check·build（含 D-7 stem 归属，纯内存）/ fmt 稳定（TEMP 影子包实测——同目录一次 spawn，per-file 结果表）；另有 workspace 上下文行
- rc：任一 ❌ → 1（CI 直接挂闸）；全 ✅/⚠️ → 0；moon 缺席/临时目录缺席 → fmt 项诚实 ⚠️ 不误报
- 全程只读（验收 4：跑前后目录快照不变）；影子包用完递归清理
- 新 FFI stub `jsonmbt_is_windows`（跨平台 shell 重定向语法分叉）
- **陷阱 #45 登记**（doctor 影子开发中实测）：`moon fmt <path>` 把 path 当项目内包过滤 pattern，项目外/非包路径**静默跳过且 rc=0**——跨项目 fmt 唯一可靠形态 = `cd <目标> && moon fmt`；fix 文案按包边界状态分叉（未接包时先接再 fmt）
- 层 2 +4 用例（无包 ❌ / 撞名 ❌ / 完整接入无 ❌ / 只读快照），20/20 绿

### Fixed（issue #13：保留字字段名 + issue #14-3：J4010 报告粒度）

- **#13 保留字字段名（`where` 等）**：修复前任一保留字键把整对象踢进 Map 逃生门——同层异类型兄弟值统一失败时泄漏出与保留字毫无关系的 `J4011 incompatible types across samples`（文案错位），单字段对象则**静默降级** `Map[String, V]`（无提示的毒产物）。修复：保留字类键（加 `_` 即合法——探针实锚 `where_` 合法 + fmt 幂等）确定性改名走 struct；类型名按**原始键**派生（`where` → `struct Where`，大写保留字合法）
- **`// jsonmbt: field-alias <Struct>.<label> = "<json键>"` 注记**（合法 MoonBit 注释，fmt 幂等）：产物头部发射非恒等改名表，build/check 预扫描注释层（moon parser 剥注释）按注记还原 JSON 键。纯语法逆映射在尾下划线邻域**数学上不可无歧义**（`where`→`where_` 与原生键 `where_` 任何确定性后缀规则都撞），显式注记是唯一全解——手写文件也因此首次能表达保留字键对象
- 撞名两级下划线：`{"where":1,"where_":2}` → 字段 `where_`/`where__` 双注记，往返无损
- **J3009**（新码，只增不改）：注记畸形（行文法）或语义错（指向不存在的 struct/字段、恒等注记、隐含 JSON 键碰撞、重复注记）一律 fail loud
- **#13 文案**：不可改名键（点号/大写开头等，本批范围外）维持 Map 逃生门，但失败文案改为点名键因（`cannot unify values under keys that are not legal MoonBit field labels ('a.b')`），不再误导用户去查不存在的跨样本异构
- **#14-3 J4010 键集分布按容器路径分组**：`at $.entries[]: 2 distinct key sets in 2 samples: ×1 { a, b }; ×1 { a, c }`——顶层/嵌套单样本键集不再与数组元素混计（修复前报 `4 distinct key sets` 把顶层 doc 也计入）；跨路径合流撞形无同容器漂移时回退全量平铺（诚实兜底）
- probe/samples 新样本对 `reserved_keys`（Vitro demo_ui_lint 形态：rules 数组含 where 字段 + 异类型兄弟）；层 2 驱动 +4 用例（往返/两份新文案 golden/J3009 门禁），16/16 绿

### Added（pages playground：P2 js 出口预演）

- `pages/` 前端 demo：JSON ↔ .json.mbt 双栏实时转换（overlay 语法高亮）+ 21 卡「能吃下什么」能力矩阵，全部过真实引擎冒烟（`pages/smoke.mjs`，22 断言）
- `pages/ffi` wrapper 包（js 后端出口三件 js_import/js_build/js_check）——src 包 js/wasm 双后端 0 错编译实测；wasm-gc String ABI 缺口（js-string-builtins 未支持）与 js release tree-shake 坑登记（PLAN §7）

### Added（§8 二次裁定：D-5 键集漂移转正）

- enum 带单参构造器字面量入 L0：降级投影 = tag 对象展开（payload 字段进顶层 + `"case"` 键；标量 payload 加 `"value"` 键）
- tag 键冲突即拒：payload struct 含 `case` 字段 → J3008（不静默覆盖）
- import 侧不自动转（缺键异构仍拒——拼错 vs 真可选无解 + 数据错误静默类型化违反 fail loud）；建模入口 = emitter 直产 / 人工改写
- vm_diff 实例：618 案例四键集 enum 建模，check/build 绿、两次 build 逐字节一致、除 tag 键全等 0 diff、变体分布 602/9/5/2 精确对上

### Added

- `jsonmbt build/check/import` CLI 三动词（D-10 rc 五值表：0/1/2/4 已占用，3 保留）
- L0 子集校验器 + 确定性降级器（紧凑与 `--pretty`/`--indent N` 形态；pretty 与 Go encoder 在键序=源序前提下逐字节一致）
- importer v1：形状签名判重 / D-1 空容器两级启发 / D-2 Int64 上浮 / 键名逃生门（Map）/ tagged-enum hint（J4030）
- `--check` 幂等闸（rc 2 + J5001）；import 产物跨文件撞名自动 stem 前缀去重（#4）
- J 系错误码 20 个（J0001–J5001，只增不改）；诊断 stderr 机器可读前缀 + 尾换行行契约
- 层 2 Go 黑盒驱动（`tests/driver`：进程契约/样本黄金/幂等证红/确定性/exe 新鲜度门禁）
- probe 实验资产：`vitro_gen`（D-6 第一档）/ `jsonmbt_go` + `fossil_batch`（第二档雏形，化石 2469 张双实现对照）
- 可执行使用手册 `src/manual.mbt.md`（mbt check fence 即锚）

### Added（§8 裁定 D-12）

- enum 无参构造器字面量入 L0：有限词表字段的写时值域校验（jsonmbt check 即红，拼错变体 J3004 列全变体；降级投影 = 变体名字符串）
- `#|` 多行字符串入 L0：长中文文本多行书写，降级 = 行净内容以 
 连接
- 边界：带 payload 构造器（E(3032)）v1 拒（观察项）；裸构造器无类型上下文拒

### Added（issue #12 处置）

- `-o -` 纯验证通道（build/import 通用）：产物改道 stdout（二进制 stub，字节契约）——CI 验证降级全链不落盘即验（check 不含降级 codegen，两者不可互替）；与 `--check`/`--fmt` 互斥（盘面语义），stdin→stdout 全管道因无绑定 stem 来源拒绝
- 补录（上批遗漏）：`import --fmt`（#10）——产物落盘后 spawn `moon fmt <单文件>` 归一 fmt-stable 形态

### Fixed

- emoji 代理对越界 panic；带点键/带点 stem 漏网；stderr 截断（issue #1）与 stdout CRLF；多诊断粘行
- （issue #12）J0002 moon fmt 失败文案：改多因列举（moon 缺 PATH vs 产物不在任何 moon workspace 覆盖——moon 原始报错经 system() 透传可见，文案引导对照），弃「is the moon toolchain installed?」单一误导；help 行声明半成功态（fmt 失败 = 产物保留未 fmt 形态 + rc=4，脚本按 rc 判红）
- （issue #12）`jsonmbt_run_cmd` Unix 分支 wait-status 解码（子进程退 1 曾会显示 rc=256；Windows system() 本就直返 exit code）——**未经 Unix 实测**（本仓 CI 面 = Windows native），Unix 环境首跑须验
- （勘误）#12 正文「报错路径退 rc=0」系提报方复现方法错误（`echo 0` 打印字面量非 `$?`）；本地重验两处均 rc=4 契约正常（提报方已在评论中撤回）
