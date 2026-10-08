# Changelog

本仓全部可见变更记录。格式与纪律见 [AGENTS.md](AGENTS.md) 纪律 6。

## [Unreleased]

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
