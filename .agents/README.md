# .agents/skills — jsonmbt 项目专属 Agent Skills

给 AI agent（及 clone 本仓库的贡献者）用的**操作手册**，覆盖那些"踩过实锤、每次都要重学"的项目流程。
格式为通用 Agent Skills 规范（目录 + `SKILL.md` + YAML frontmatter），**不绑定任何特定工具**。

## 与 AGENTS.md 的分工

- `AGENTS.md`（根）：每批都读入的**静态纪律与路由**，必须保持克制；
- `.agents/skills/`：**按需触发**的详细操作手册——agent 在命中触发场景时才加载，不占常驻上下文；
- 时点性事实（测试数、里程碑状态）一律以 PLAN §5 里程碑表与测试运行结果为权威，skill 只写流程与陷阱。

## 清单

| Skill | 触发场景 |
|---|---|
| `jsonmbt-workspace-review` | 审阅未提交改动 / 最近提交批 / 人写脚本与方案主张（五阶段规程 + 演化机制） |

## 安装

**ZCode 用户无需安装**：ZCode 直接扫描工作区 `.agents/skills/`。
其他工具（Claude Code 等）按通用 Agent Skills 格式把目录复制到各自 skill 目录即可；删除即卸载。

## 维护义务

改动 skill 覆盖的流程（门禁、CLI 契约、判据口径）时**连坐更新**对应 `SKILL.md`；
每个 skill 的演化与变更纪律见其 `references/05-演化机制.md`。
