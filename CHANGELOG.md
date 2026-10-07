# Changelog

本仓全部可见变更记录。格式与纪律见 [AGENTS.md](AGENTS.md) 纪律 6。

## [Unreleased]

### Added

- `jsonmbt build/check/import` CLI 三动词（D-10 rc 五值表：0/1/2/4 已占用，3 保留）
- L0 子集校验器 + 确定性降级器（紧凑与 `--pretty`/`--indent N` 形态；pretty 与 Go encoder 在键序=源序前提下逐字节一致）
- importer v1：形状签名判重 / D-1 空容器两级启发 / D-2 Int64 上浮 / 键名逃生门（Map）/ tagged-enum hint（J4030）
- `--check` 幂等闸（rc 2 + J5001）；import 产物跨文件撞名自动 stem 前缀去重（#4）
- J 系错误码 20 个（J0001–J5001，只增不改）；诊断 stderr 机器可读前缀 + 尾换行行契约
- 层 2 Go 黑盒驱动（`tests/driver`：进程契约/样本黄金/幂等证红/确定性/exe 新鲜度门禁）
- probe 实验资产：`vitro_gen`（D-6 第一档）/ `jsonmbt_go` + `fossil_batch`（第二档雏形，化石 2469 张双实现对照）
- 可执行使用手册 `src/manual.mbt.md`（mbt check fence 即锚）

### Fixed

- emoji 代理对越界 panic；带点键/带点 stem 漏网；stderr 截断（issue #1）与 stdout CRLF；多诊断粘行
