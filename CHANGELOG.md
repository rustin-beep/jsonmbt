# Changelog

本仓全部可见变更记录。格式与纪律见 [AGENTS.md](AGENTS.md) 纪律 6。

## [Unreleased]

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
