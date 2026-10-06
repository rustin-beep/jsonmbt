# jsonmbt 视觉资产

主图形「弯月括号」：**左括号收成弯月，月牙内缘长出括号中尖**——同一个形状的两种读法（弯月即花体 `{`），右侧暖白 `}` 与之**端头对齐**（上下端同水平线）呼应成一对，中缝负空间即被包裹的数据。寓意：月 = MoonBit，括号对 = JSON，两形状间 = 「源 → 产物」的确定性投影通道。月牙与中尖均为书法变宽笔画（两端出锋、下尖拖小锋），与 Yellowtail 连笔 wordmark 同一支笔的叙事。

> 演化记录：v3 曾在月牙凹处放空心点（`null` 双关），被指认出「眼睛」格式塔（凹弧+圆点=眼球+瞳孔）后删除——`null`/bit 双关留档，供将来文档插画回收。

wordmark `jsonmbt` 用 Yellowtail 连笔书法（羽毛笔气质），已转矢量 path 内嵌。

## 色系：暖夜三色（用户裁定：排除深蓝与蓝紫渐变；黄色须掺色非纯黄）

| 用途 | 色值 |
|---|---|
| 主底（暗版） | `#17181C` 炭黑 |
| 右括号 / wordmark（暖白） | `#F2EDE3` |
| 弯月 / 中尖 / ⇄（蜜蜡黄） | `#E3A83F`——JSON 黄掺橙与棕的去艳版，烛光蜜色 |
| banner 内 icon 层次底 | `#101115` |
| tagline | `#D8D2C6`（20px + 0.05em 字距，与 wordmark 同区层级） |

白与蜜的对比即"语法 vs 数据"：括号是语法容器（暖白），月与点是内容（蜜蜡黄）。亮底反色版：暖白底 + 炭黑图形 + 蜜黄加深 `#C8892D`。

## 文件

| 文件 | 用途 |
|---|---|
| `logo.svg` | 主 icon（GitHub 头像 / favicon 源），256 视区 |
| `logo-inverse.svg` | 亮底反色版 |
| `logo-mono.svg` | 纯黑透明底单色版（打印 / CLI） |
| `banner.svg` | README 横幅：icon + 连笔 wordmark + tagline + ⇄ |
| `logo-256.png` / `logo-512.png` | GitHub 头像上传用（GitHub 不收 SVG 头像） |
| `banner.png` | 横幅 PNG 备份 |

## 纪律

- **SVG 是唯一真相源**；所有 PNG 由 SVG 派生，禁止直接编辑 PNG。
- 图形全部为闭合 path（书法月牙/括号由中轴点列 + Catmull-Rom 平滑 + 变宽法线偏移生成；空心点为 `<circle>` 描边），零字体依赖。
- **修改图形须同步四处**：`logo.svg` / `logo-inverse.svg` / `logo-mono.svg` / `banner.svg` 内嵌组。笔触数据源 `tmp/paths.json`（键：`crescent` / `rightBrace`）与组装脚本 `tmp/build_logo_v3.py` 若被清理，需从 git 历史恢复生成器。
- wordmark 为 Yellowtail（Apache License 2.0，Google Fonts）字形转 path（fontTools SVGPathPen）；内层 translate 必须用字体单位，乘 scale 会二次缩放导致字形叠罗汉（v2 踩过的坑）。
- banner 内 wordmark 起点 x=162；改 wordmark 须重算 `total_advance × scale` 防撞 ⇄。

## 再生成 PNG（Windows，Edge headless）

```bash
E="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
"$E" --headless=new --disable-gpu --user-data-dir="D:/code/jsonmbt/tmp/edgeprof1" \
  --screenshot="D:/code/jsonmbt/assets/logo-256.png" --window-size=256,256 \
  "file:///D:/code/jsonmbt/assets/logo.svg"
```

- 512px 需 HTML 包装放大：`<body style="margin:0"><img src=".../logo.svg" width="512" height="512"></body>` 后按窗口截。
- Git Bash 陷阱：双反斜杠路径里 `$var` 会被转义成字面量，统一用正斜杠。
- Edge headless 并发截图须每实例独立 `--user-data-dir`，否则 profile 锁静默失败；改 SVG 后重渲染时注意别读到旧 PNG 缓存。

## 已知边界

- 16px favicon 下中尖细节变钝（退化为"月牙+括号"仍可读）；favicon 直接用 icon 而非 wordmark——Yellowtail 竖笔画（j 下伸 / t 上伸）在小尺寸浅色场景会糊，如需字标版 favicon 须单独画紧排版。
- banner 内嵌 icon 已放大至约 80% 画布（scale 1.12，rx 36）；wordmark 起点 x=174 与 icon 保持 36px 间距（j 起笔锋曾贴撞括号）。独立 `logo.svg` 保留较松的留白（GitHub 头像裁圆场景更稳）。
- 书法月牙/括号/中尖均为程序生成的变宽形态（中轴点列 × 宽度曲线），非字体字形。
