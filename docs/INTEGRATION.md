# 在你的仓里接入 `.json.mbt`

> 本文是**面向下游仓**的接入指引。Vitro 的完整迁移实录（11 张 rules.json + 门禁证据）在
> `rustin-beep/Vitro` 的 `docs/current/07-质量与裁定/20261007_jsonmbt真相源迁移.md`。

## 为什么要多这一步（buying reason）

`.json.mbt` 的价值不在"更好读"，而在**MoonBit 编译器会替你看数据**：

| 缺陷 | `.json` | `.json.mbt` |
|---|---|---|
| 字段类型写错（`Int` 字段填字符串） | 运行时才炸，或干脆不炸 | **编译期红** `[4014]` |
| 字段名拼错 | 静默忽略 | **编译期红** `[4044]` / `[4091]` |
| 字段缺失 | 静默用零值 | **编译期红** `[4044]` |
| 格式漂移 | 无感知 | `moon fmt` 归一 |

但这个价值**有前提**——文件不在 MoonBit 的包边界内，moon 就完全看不见它，等于白付成本。
本文就是那套前提的完整接法，全部结论都是实测出来的。

## 三个前提（缺一即失效）

### ① 所在目录必须带 `moon.pkg`

moon 只把**自带 `moon.pkg` 的目录**当包并编译其中的 `.json.mbt`。实测：只在仓根放一个
`moon.pkg` 时 `moon check` 报 `ran 1 task`（文件根本没被读）；给每个含 `.json.mbt` 的目录
各加一个，任务数才涨起来、才开始真正检查。

```bash
printf '\n' > data/moon.pkg      # 1 字节换行，即"空块"
```

⚠️ **只能空块**。实测 `{}` 与块式 `import (\n)` 两种写法**都报**
`Failed to calculate build plan`。

### ② `struct` 必须 `pub`

```moonbit
pub struct Config { port : Int }   # ✅
struct Config { port : Int }       # ❌ priv → 逐字段 unused_field 噪音 + moon info 不透明
```

`moon info` 对 priv struct 只给不透明的 `type X`——而 `moon info` 产出的接口面正是
`.json.mbt` 白嫖来的 schema 出口（见下文「`.mbti` 入仓」）。

### ③ 经 `moon fmt` 归一

`moon fmt` 会做两件事：给顶层 `struct` / `let` 补 `///|` 文档标记；**按行宽决定 record
折行**（短的折成单行、长的保持多行），大 Map 会逐项展开。import 产物**不是** fmt-stable
形态，所以这一步不能跳。

实测副作用是好的：**归一前后 `build` 产物不变**（7 张字节相等 + 4 张仅缩进风格差、值相等），
即 fmt 只改形态不改语义。

## 最小接入（单模块仓）

```bash
# 1. 转换（产物与源同目录同名 .json.mbt）
jsonmbt import data/config.json          # → data/config.json.mbt

# 2. 声明包边界
printf '\n' > data/moon.pkg

# 3. 归一 + 检查
moon fmt data
moon check
```

之后 `.json.mbt` 就是唯一真相源，`.json` 由 `jsonmbt build --pretty` 再生给下游消费者
（`build` 默认输出紧凑 JSON；**若下游按字节锚定对账，必须加 `--pretty`**，它对齐 Go
`json.Encoder.SetIndent` 的形态）。

## 多模块仓：`moon.work`

若仓里有多个 moon 项目（`moon.mod` 各在各的目录），在**仓根**加 `moon.work`，一条命令
覆盖全部：

```bash
moon work init
moon work use path/to/module-a
moon work use path/to/module-b
# 生成：members = ["./path/to/module-a", "./path/to/module-b"]
```

```bash
moon check          # 覆盖全部成员
moon fmt <member>   # ⚠️ 限定成员，见下方坑表
```

`members: [...]` / `include "..."` 两种手写语法**都报解析错**，必须用 `moon work` 命令生成。

## CI 接线（GitHub Actions）

```yaml
      - uses: hustcer/setup-moonbit@v1
        with:
          version: latest

      # ① 静态门禁：真相源坏了这里就红（类型错/字段错在编译期拦下）
      - name: .json.mbt static gate
        shell: bash
        run: moon check

      # ② 再生 .json 供下游消费（消费方零改动）
      - name: Regenerate .json
        shell: bash
        run: |
          set -e
          for m in $(find . -name '*.json.mbt' -not -path './_build/*'); do
            jsonmbt build --pretty "$m"
          done
```

`moon check` 应放在再生**之前**：真相源非法时 `build` 也会红（`J1001`/`J2003`/`J3004`），
但先拦在编译期更快、诊断更准。

### `.mbti` 入仓还是 gitignore？

两种做法都见过，**跟随你仓里既有的约定**：

- 若仓里已有 `pkg.generated.mbti` 入仓（Vitro 的 `moonbit/` 下有 25 个）→ scripts 侧也入仓。
  它是 `moon info` 生成的接口面，含 `.json.mbt` 的 struct 类型，**白嫖的 schema 出口**，
  也是"哪些 `.json.mbt` 在编译面内"的可读清单。实测内容稳定（重生成 md5 不变）。
- 否则 gitignore 掉，别让副产物污染提交。

## 验证你的接入真的生效（注入测试法）

光跑绿说明不了问题——**必须注入错误证明它会红**。两个要点：

1. **哨兵先自证**：注入后先打印文件内容确认改动落地，再看 rc。
2. **必须跨类型注入**：把 `String` 字段声明改成 `Int`（或反之）。**同类型改数值不会红，
   而且这是正确的**——moon 抓类型/字段，不抓业务语义。业务语义（如"分层号写错了"）
   得由下游自己的门禁抓，两者互补。

```bash
cp data/config.json.mbt /tmp/bak
sed -i 's/^  schema : Int$/  schema : String/' data/config.json.mbt
grep -n 'schema : ' data/config.json.mbt    # ← 自证：确认改动落地
moon check                                   # ← 期望非 0，诊断含 [4014]
cp /tmp/bak data/config.json.mbt
```

判据：`rc ≠ 0` 且诊断码与预期一致。`moon check` 在 Windows 上错误退出码是 `127`。

## 坑表（全部实测，勿再踩）

| 坑 | 表现 | 正解 |
|---|---|---|
| 文件不在带 `moon.pkg` 的目录 | `moon check` 报 `ran 1 task` / "no work to do"，文件根本没被读 | 逐目录加 `moon.pkg` |
| `moon.pkg` 写成 `{}` 或 `import ()` | `Failed to calculate build plan` | 空块（1 字节换行） |
| `moon build` 当门禁 | 注入类型错仍 rc=0 | 用 `moon check`（或 `moon test`） |
| `moon check`（全量）当门禁 | 跳过孤立包 | 仓根 `moon.work` + `moon check` |
| workspace 根跑无参数 `moon fmt` | **重排无关模块的源文件**（实测改了 `moonbit/codegen/addr.mbt` 13 行） | `moon fmt <member>` 限定成员 |
| YAML step name 含 `: ` | 整个 yml 解析失败（`mapping values are not allowed here`） | 给含冒号的值加引号 |
| 注入用同类型改数值 | 不红，且**这是正确的** | 跨类型注入；业务语义交给下游门禁 |
| 只在文件尾追加 `pub let` 验证 | 不红——**两个 `pub let` 在 MoonBit 语法上合法**（moon 不知单文档基数） | 注入到字段声明/值上 |
| `moon test` 门禁没跑 | 缺 registry 索引时依赖解析阶段就红 | CI 先 `moon update` |

## moon 的行为基线（2026-09 工具链实测）

| 命令 | 隔离立的包（含 `.json.mbt`） |
|---|---|
| `moon build` | ❌ 注入类型错仍 rc=0 |
| `moon test` | ✅ rc≠0（但只编译到测试目标，空跑无测试的包时价值有限） |
| `moon check`（全量） | ❌ 跳过孤立包 |
| `moon check`（`moon.work` 根级） | ✅ 覆盖全部成员 |
| `moon check <成员名当路径>` | ❌ "no work to do"——成员名不被当作路径 |

> 判定 moon 是否真检查了某个文件，**不能信 task 数或 "no work to do"**。用
> `moon check --dry-run | grep 'workspace-path'` 看真实编译单元，再用注入测试看 rc。
