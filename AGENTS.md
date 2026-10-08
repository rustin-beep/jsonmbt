# jsonmbt Agent 指南

> 定位：`.json.mbt` —— JSON 的类型化源码形态（MoonBit 子集 + 确定性降级）。
> **计划权威 = [docs/PLAN.md](docs/PLAN.md)**（里程碑/决策记录/规范决策点全在那里，本文件只立每批都用的纪律）；**状态唯一载体 = PLAN §5 里程碑表**。
> 语言陷阱见 [docs/MOONBIT_PITFALLS.md](docs/MOONBIT_PITFALLS.md)（Vitro 仓一手实证快照）。

## 纪律

1. **必须中文输出思考与回答**。
2. **未经允许禁止 git 提交；push 恒需单独授权**。提交信息用分栏报告体（type + 标题 + 分节正文）；提交信息中提及用户（署名/审阅标记）= 该批经深度审阅的信号，未标明仅代表浏览过。
3. **实测大于脑测、统一真相来源**：结论来自亲跑命令/亲读代码；文档数字单点归一（测试数等计数真值入测试运行结果，文档只引用）；禁时点句当现况（PLAN 状态唯一载体的同款纪律延伸到全部文档）。
4. **诚实记录**：对拍标准 = **RFC 8259 + moon 实测行为**（本仓无 oracle——与 Vitro 的关键差异）；任何与标准不符之处必须登记，禁止改测试预期粉饰。
5. **红→绿纪律**：每个缺陷修复先有会失败的用例，修复提交引用用例名；护栏/闸门必须先证红（J9 埋雷义务）。
6. **文档体系**：新文档进 `docs/`；CHANGELOG 从第一笔起执行「`[Unreleased]` 全文唯一一段，新条目追加到既有小节、禁止新插第二个标题」（Vitro 曾堆出四段重复 Unreleased，agent 引用即幻觉）。
7. **防线双层纪律**：**内层 = moon test 语义锚**（纯函数单元锚：推断规则/降级器/诊断——随工具链漂移但漂移即编译红、fail loud 可接受，由工具链探针兜底）；**外层 = Go 黑盒驱动（稳定防线，独立于 moon 工具链——只依赖 exe 产物）**：CLI 进程契约（rc/stdout/stderr 逐字节 vs golden）、import→build 进程链往返等价、确定性断言（两次 build 逐字节 diff）、压力测试（编译一次跑 N 轮取分布）。**对外承诺的真防线在层 2**：外部语言调用、CI 门禁、性能回归全在层 2——moon test 红了先查工具链漂移，层 2 红了才是产品真缺陷。一次性勘探脚本（Python/Go）不入防线；`jsonmbt check` 是产品功能而非 CI 专属闸。层 2 复用 Vitro 模式：exe 新鲜度门禁、golden 逐字节管理、校验和计时纪律。**`.mbtx` 脚本仅作一次性内部工具，禁止用于层 2 防线或 moon 自身行为探针**（用 moon 测 moon = 自证，违反层 2 独立性）。
8. **工具陷阱**：`| head` 会 SIGPIPE 杀进程（判失败前 tail 全量）；管道 `$?` 是尾命令退出码（PIPESTATUS 或裸命令）；哨兵先证红再采信；基准对照校验和逐位一致才计时；Windows 路径 grep 用 `[/\]` 双兼容；**跨会话/跨 target 消费 `_build` 产物前先清增量重建**（缓存毒化「同源不同果」——陷阱快照 #41）；子目录裸跑 `moon build` 会向上冒泡找最近构建文件作 root（行为验证前确认 cwd=root——陷阱 #47）；构建报「拒绝访问 (os error 5)」= 产物文件被外部句柄持有，瞬时句柄重试即愈、频发用 `--target-dir` 换产物目录（真因是避开被持文件非绕锁——陷阱 #48）。
9. **MoonBit native 构建默认 clang**：一律 `MOON_CC=clang` 后再 `moon build --target native`（MSVC 撞 moon#2254 构建悬崖）；另新增包或出口面须同步登记接口面与测试。
10. **求值分级冻结（L0–L2）**：语言面（.json.mbt 能写什么）变更必须走 PLAN §8 分级评审——**消费者是自家（Vitro）也不跳级**；工具面（build/check/diff 输出形态）可自由加。规范决策点（D-1/D-2）未拍板前不在实现里偷跑。
11. **生成与检查契约**（从 Vitro 事故直接继承）：`--check` 幂等 = flag 包解析（非手工 os.Args，`-check` 单横线静默改写产物的事故不许重演）、生成流程内置 `moon fmt`、check 无写副作用、产物首行 `///|` + `@generated` 标注、行尾归一后比对。
12. **探针先行**：新能力/新边界先跑一次性探针拿一手真值（Python/Go 皆可），结论进 PLAN 再实装——importer 探针（label 矩阵/推断原型/大文件性能）是本仓先例。
13. **`.json.mbt` 要吃到 moon 静态检测，三个前提缺一不可**（2026-10-07 实测定线，Vitro 迁移返工两轮换来）：
    ① **必须在带 `moon.pkg` 的目录内**——不在 moon workspace/包边界内的文件，moon 工具链**完全看不见**（Vitro 把 `.json.mbt` 放 `scripts/` 下、`moon.mod` 在 `moonbit/`，11 张文件全部处于包外，等于只换载体没买到静态检查）；② **struct 必须 `pub`**——priv 触发逐字段 `unused_field` 噪音，且 `moon info` 不透明；③ **经 `moon fmt` 归一**——fmt 会补 `///|` 文档标记，并按行宽决定 record 折行（短 record 折成单行），import 产物不是 fmt-stable 形态。
    **实测的 moon 行为基线**：`moon build` **不**检查孤立包类型（注入类型错仍 rc=0）；`moon test` **会**（rc=1 `[4014]`）；`moon check` 全量**跳过**孤立包，`moon check <包名>` 才点名检查。CI 的 L1-b + L1-c 覆盖此防线。
    **导入 ≠ 合格**：importer 反推的 struct 名是机械派生的（`Id`/`Id2`/`Print_int`），零信息量，损害「人写形态」核心价值——**人工审阅命名是必需环节，不能跳**。

## 环境注意

- 探针/生成物临时件放 `notes/` 或 `tmp/`。**注意：`tmp/<dir>/` 一旦放 `moon.pkg` 就会成为独立包进入全量 `moon check` 编译面**（审阅实测注入即红；**`.gitignore` 不豁免此扫描，嵌套 module〔自带 `moon.mod`/`moon.work`〕才是唯一边界**——陷阱 #46）——探针目录勿带 `moon.pkg`，实验完即删；根目录 .mbt 同包全编译。
- 样本锚三层：JSON 输入 → 期望 `.json.mbt` → 期望降级产物——改一处连跑全部。
- **`examples/` 与 `probe/samples/` 是 moon 包**（各有 `moon.pkg`）——里面的 `.json.mbt` 由此进入 moon 编译面受静态检查保护；**新增 `.json.mbt` 样本默认放这两个目录**，别另起无 `moon.pkg` 的目录（那就白写了）。
