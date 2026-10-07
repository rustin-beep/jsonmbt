## 改了什么 / 为什么

<!-- 一句话说清动机；涉及时点句的请写成现况句 -->

## 验证

- [ ] `MOON_CC=clang moon build --target native` 绿
- [ ] `moon test --target native` 绿（L1 内层语义锚）
- [ ] `go run ./tests/driver -exe <产物>` 绿（L2 外层黑盒驱动）
- [ ] 新增 / 修改的接口面已同步登记（`pkg.generated.mbti` 与测试）

## 红线自检

- [ ] **红→绿**：修复类改动先有会失败的用例，本 PR 引用了用例名；新增闸门已先证红
- [ ] **求值分级**：本 PR 是否触碰语言面（`.json.mbt` 能写什么）？
  - 否（仅工具面：`build` / `check` 输出形态）—— 可自由改
  - 是 —— 已走 PLAN §8 分级评审并关联 issue：<!-- 链 issue -->
- [ ] **诚实记录**：没有靠改测试预期来让门禁变绿；与 RFC 8259 / moon 实测不符之处已登记进 PLAN
- [ ] **CHANGELOG**：如需更新，条目追加进既有 `[Unreleased]` 小节（全文唯一一段，不新插标题）
- [ ] 生成类改动满足契约：`--check` 幂等、无写副作用、产物首行 `///|` + `@generated`

## 影响面

<!-- 是否影响 golden 文件 / 诊断编号（J 系） / 退出码契约；有则列出 -->
