// jsonmbt 层 2 黑盒驱动雏形（防线的对外承诺层——AGENTS 纪律 7）：
// 只依赖 exe 产物、独立于 moon 工具链；golden 逐字节、rc 五值、幂等闸、
// 确定性断言。第一条用例即 issue #1 的红→绿锚（stderr 多字节截断——
// golden 逐字节比对拦得住的第一条实锤）。
//
// 运行：go run ./tests/driver [-exe <jsonmbt.exe>]
// 退出码：0 全过 / 1 有失败（用例名单打印）。
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

var exePath = flag.String("exe", "", "jsonmbt exe 路径（默认探测 _build 常见产物位）")

// runExe 在工作目录 dir 下以相对路径参数执行，返回 rc/stdout/stderr。
func runExe(exe, dir string, args ...string) (int, []byte, []byte, error) {
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	rc := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		rc = exitErr.ExitCode()
	} else if err != nil {
		return -1, nil, nil, err
	}
	return rc, out.Bytes(), errb.Bytes(), nil
}

func writeFile(dir, name, content string) string {
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		panic(err)
	}
	return p
}

type testCase struct {
	name string
	run  func(exe, dir string) error
}

// J2003-emdash-stderr-bytes：issue #1 的红→绿锚。
// 诊断含 em-dash（1 码元 / 3 UTF-8 字节）时 stderr 必须逐字节完整——
// 修复前按码元数写入，尾部丢 2 字节（document → docume）。
func caseEmdashStderr(exe, dir string) error {
	writeFile(dir, "j.json.mbt",
		"struct S {\n  a : Int\n}\npub let server : S = S::{ a: 1 }\n")
	rc, _, stderr, err := runExe(exe, dir, "check", "j.json.mbt")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1", rc)
	}
	want := []byte("jsonmbt: error [J2003] j.json.mbt:4:1 top-level binding is 'server' but the file stem is 'j'\n" +
		"  help: rename the binding (or the file) so they match — this keeps one name per document\n") // 尾 \n = 行契约（审 P2-2）
	if !bytes.Equal(stderr, want) {
		return fmt.Errorf("stderr 逐字节不符（golden vs 实际）：\n--want--\n%q\n--got--\n%q", want, stderr)
	}
	return nil
}

// build-stdout-deterministic：同输入两次 build，stdout 逐字节一致（D-8 确定性）。
func caseBuildDeterministic(exe, dir string) error {
	stdin := "struct T {\n  v : Int\n  s : String\n}\npub let d : T = T::{ v: 1, s: \"x\" }\n"
	rc1, out1, _, err := runExeWithStdin(exe, dir, stdin, "build", "-")
	if err != nil {
		return err
	}
	rc2, out2, _, err := runExeWithStdin(exe, dir, stdin, "build", "-")
	if err != nil {
		return err
	}
	if rc1 != 0 || rc2 != 0 {
		return fmt.Errorf("rc = %d/%d, want 0/0", rc1, rc2)
	}
	if !bytes.Equal(out1, out2) {
		return fmt.Errorf("两次 build stdout 不一致（确定性破坏）")
	}
	return nil
}

// import-check-idempotent：幂等闸绿（rc 0）→ 篡改产物证红（rc 2 + J5001）。
func caseImportCheckGate(exe, dir string) error {
	// 语料含嵌套对象（审 P1：原语料无嵌套 → 不产嵌套 struct → scan/幂等
	// 的牙口测不到；嵌套 struct 命名级联漂移曾打翻本闸）
	writeFile(dir, "g.json", "{\"k\": [1, 2], \"u\": \"http://x/y\", \"cfg\": {\"id\": 1, \"name\": \"n\"}}\n")
	if rc, _, _, err := runExe(exe, dir, "import", "g.json"); err != nil || rc != 0 {
		return fmt.Errorf("import rc=%d err=%v", rc, err)
	}
	rc, _, _, err := runExe(exe, dir, "import", "g.json", "--check")
	if err != nil {
		return err
	}
	if rc != 0 {
		return fmt.Errorf("幂等应绿：rc = %d, want 0", rc)
	}
	// 篡改产物后必须红（J9 埋雷义务的常驻化）
	if err := os.WriteFile(filepath.Join(dir, "g.json.mbt"), []byte("// tampered\n"), 0o644); err != nil {
		return err
	}
	rc, _, stderr, err := runExe(exe, dir, "import", "g.json", "--check")
	if err != nil {
		return err
	}
	if rc != 2 {
		return fmt.Errorf("篡改后应 rc 2, got %d", rc)
	}
	if !bytes.Contains(stderr, []byte("[J5001]")) {
		return fmt.Errorf("stderr 应含 [J5001]，got %q", stderr)
	}
	return nil
}

// usage-rc4：无参/未知动词 → rc 4（D-10 用法错）。
func caseUsageRC4(exe, dir string) error {
	for _, args := range [][]string{{}, {"frobnicate", "x"}} {
		rc, _, _, err := runExe(exe, dir, args...)
		if err != nil {
			return err
		}
		if rc != 4 {
			return fmt.Errorf("args=%v rc = %d, want 4", args, rc)
		}
	}
	return nil
}

func runExeWithStdin(exe, dir, stdin string, args ...string) (int, []byte, []byte, error) {
	cmd := exec.Command(exe, args...)
	cmd.Dir = dir
	cmd.Stdin = strings.NewReader(stdin)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	rc := 0
	if exitErr, ok := err.(*exec.ExitError); ok {
		rc = exitErr.ExitCode()
	} else if err != nil {
		return -1, nil, nil, err
	}
	return rc, out.Bytes(), errb.Bytes(), nil
}

// exeFreshness：exe mtime 必须晚于全部构建输入（src/ cmd/ moon.mod）——
// 旧 exe 跑出假绿（审 P2-3；Vitro 模式的最小版，校验和门禁随后续扩面）。
func exeFreshness(exe string) error {
	st, err := os.Stat(exe)
	if err != nil {
		return err
	}
	exeMtime := st.ModTime()
	var stale []string
	root := "."
	for _, dir := range []string{"src", "cmd"} {
		filepath.WalkDir(filepath.Join(root, dir), func(path string, d os.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return nil
			}
			name := d.Name()
			isTest := strings.HasSuffix(name, "_test.mbt") || strings.HasSuffix(name, "_wbtest.mbt") || strings.HasSuffix(name, ".mbtx")
			if (strings.HasSuffix(name, ".mbt") || strings.HasSuffix(name, ".c") || name == "moon.pkg") && !isTest {
				if fi, err := d.Info(); err == nil && fi.ModTime().After(exeMtime) {
					stale = append(stale, path)
				}
			}
			return nil
		})
	}
	for _, f := range []string{"moon.mod", "moon.pkg"} {
		if fi, err := os.Stat(f); err == nil && fi.ModTime().After(exeMtime) {
			stale = append(stale, f)
		}
	}
	if len(stale) > 0 {
		return fmt.Errorf("exe stale (rebuild first: MOON_CC=clang moon build --target native cmd/jsonmbt): newer inputs: %v", stale)
	}
	return nil
}

// probeSamplesGolden：probe/samples 三层锚真门禁（审 P2-2：样本无 runner
// 且不在编译面 = 摆设）——每个 *.json.mbt 必须 check 过 + build 产物与
// 同名 .json golden 逐字节一致。
func caseProbeSamples(exe, dir string) error {
	entries, err := os.ReadDir(filepath.Join("probe", "samples"))
	if err != nil {
		return fmt.Errorf("probe/samples 不可读: %w", err)
	}
	ran := 0
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, ".json.mbt") {
			continue
		}
		ran++
		src, err := os.ReadFile(filepath.Join("probe", "samples", name))
		if err != nil {
			return err
		}
		golden, err := os.ReadFile(filepath.Join("probe", "samples", name[:len(name)-len(".mbt")]))
		if err != nil {
			return fmt.Errorf("样本 %s 缺 .json 黄金: %w", name, err)
		}
		if rc, _, _, err := runExeWithStdin(exe, dir, string(src), "check", "-"); err != nil || rc != 0 {
			return fmt.Errorf("样本 %s check rc=%d err=%v", name, rc, err)
		}
		rc, out, _, err := runExeWithStdin(exe, dir, string(src), "build", "-")
		if err != nil || rc != 0 {
			return fmt.Errorf("样本 %s build rc=%d err=%v", name, rc, err)
		}
		// 尾部行尾（Windows runtime println 发 \r\n）不属产物语义：双侧归一后逐字节比
		got := bytes.TrimRight(out, "\r\n")
		want := bytes.TrimRight(golden, "\r\n")
		if !bytes.Equal(got, want) {
			return fmt.Errorf("样本 %s build 产物与黄金不一致\n--golden--\n%q\n--got--\n%q", name, want, got)
		}
	}
	if ran == 0 {
		return fmt.Errorf("probe/samples 无样本（门禁空转）")
	}
	return nil
}

// pretty-vs-go-encoder：--pretty 产物与 Go json.Encoder 逐字节对拍（前提
// 限定：键序=源序——Go struct 字段声明序；Go map 序列化走字典序不在此
// 对拍域，见 pretty-key-order 用例锚定 jsonmbt 自身源序语义）。审 P1：
// 该卖点此前零门禁，宣称长期成立却无对拍——本用例即补牙。
func casePrettyVsGoEncoder(exe, dir string) error {
	type inner struct {
		B int      `json:"b"`
		A []string `json:"a"`
	}
	type doc struct {
		Z     inner  `json:"z"`
		Title string `json:"title"`
		Count int64  `json:"count"`
		OK    bool   `json:"ok"`
		Empty []int  `json:"empty"`
		Note  string `json:"note"`
	}
	d := doc{inner{2, []string{"x", "y"}}, "títle—em", 9223372036854775807, true, []int{}, "a\"q\n"}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(d); err != nil {
		return err
	}
	want := buf.Bytes()
	src := "pub struct Z {\n" +
		"  b : Int\n" +
		"  a : Array[String]\n" +
		"}\n" +
		"pub struct Doc {\n" +
		"  z : Z\n" +
		"  title : String\n" +
		"  count : Int64\n" +
		"  ok : Bool\n" +
		"  empty : Array[Int]\n" +
		"  note : String\n" +
		"}\n" +
		"pub let doc : Doc = Doc::{\n" +
		"  z: Z::{ b: 2, a: [\"x\", \"y\"] },\n" +
		"  title: \"títle—em\",\n" +
		"  count: 9223372036854775807,\n" +
		"  ok: true,\n" +
		"  empty: [],\n" +
		"  note: \"a\\\"q\\n\",\n" +
		"}\n"
	writeFile(dir, "doc.json.mbt", src)
	if rc, _, stderr, err := runExe(exe, dir, "build", "--pretty", "doc.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v stderr=%s", rc, err, stderr)
	}
	got, err := os.ReadFile(filepath.Join(dir, "doc.json"))
	if err != nil {
		return err
	}
	if !bytes.Equal(bytes.TrimRight(got, "\r\n"), bytes.TrimRight(want, "\r\n")) {
		return fmt.Errorf("--pretty 与 Go encoder 字节不符\n--want--\n%q\n--got--\n%q", want, got)
	}
	return nil
}

// pretty-key-order：键序=源序语义锚（非字典序）——jsonmbt 的确定性承诺
// 是源序投影；防止把 --pretty "修"成字典序去对齐 Go map（另一语义域）
func casePrettyKeyOrder(exe, dir string) error {
	oSrc := "pub let o = { \"b\": 1, \"a\": 2 }\n"
	writeFile(dir, "o.json.mbt", oSrc)
	rc, out, _, err := runExeWithStdin(exe, dir, oSrc, "build", "--pretty", "-")
	if err != nil || rc != 0 {
		return fmt.Errorf("rc=%d err=%v", rc, err)
	}
	want := []byte("{\n  \"b\": 1,\n  \"a\": 2\n}\n")
	if !bytes.Equal(bytes.TrimRight(out, "\r\n"), bytes.TrimRight(want, "\r\n")) {
		return fmt.Errorf("键序应保持源序（b,a）非字典序（a,b）:\n%q", out)
	}
	return nil
}

// stderr-line-contract：多诊断连发不粘行（审 P2-2 红证常驻化）
func caseStderrLineContract(exe, dir string) error {
	writeFile(dir, "c1.json.mbt", "pub let c1 = 1 +\n")
	writeFile(dir, "c2.json.mbt", "pub let c2 = 2 +\n")
	rc, _, stderr, err := runExe(exe, dir, "check", "c1.json.mbt", "c2.json.mbt")
	if err != nil || rc != 1 {
		return fmt.Errorf("rc=%d err=%v", rc, err)
	}
	lines := strings.Split(strings.TrimRight(string(stderr), "\r\n"), "\n")
	if len(lines) != 4 {
		return fmt.Errorf("应 4 行（2 诊断 × 2 行），得 %d 行：%q", len(lines), stderr)
	}
	for i, l := range lines {
		if strings.Contains(l, "literalsjsonmbt:") {
			return fmt.Errorf("诊断粘行实锤（第 %d 行）: %q", i, l)
		}
	}
	return nil
}

// cli-hints（#6-2/#6-3）：import 落盘提示 moon fmt；build 未带 --pretty
// 提示字节锚定风险（带 --pretty 时静默）
func caseCliHints(exe, dir string) error {
	writeFile(dir, "h.json", "{\"k\": 1}\n")
	rc, _, stderr0, err := runExe(exe, dir, "import", "h.json")
	if err != nil || rc != 0 {
		return fmt.Errorf("import rc=%d err=%v", rc, err)
	}
	if !strings.Contains(string(stderr0), "moon fmt") {
		return fmt.Errorf("import 应提示 moon fmt，got %q", stderr0)
	}
	rc, _, stderr1, err := runExe(exe, dir, "build", "h.json.mbt")
	if err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v stderr=%s", rc, err, stderr1)
	}
	if !strings.Contains(string(stderr1), "--pretty") {
		return fmt.Errorf("build 缺 --pretty 应 hint，got %q", stderr1)
	}
	rc, _, stderr2, err := runExe(exe, dir, "build", "--pretty", "h.json.mbt")
	if err != nil || rc != 0 {
		return fmt.Errorf("build --pretty rc=%d err=%v", rc, err)
	}
	if len(stderr2) != 0 {
		return fmt.Errorf("--pretty 应静默，got %q", stderr2)
	}
	// --indent 1（#6-1）：1 空格缩进形态锚
	tSrc := "pub let t = { \"a\": 1, \"b\": [1] }\n"
	rc, out, _, err := runExeWithStdin(exe, dir, tSrc, "build", "--pretty", "--indent", "1", "-")
	if err != nil || rc != 0 {
		return fmt.Errorf("indent rc=%d err=%v", rc, err)
	}
	want := []byte("{\n \"a\": 1,\n \"b\": [\n  1\n ]\n}\n")
	if !bytes.Equal(bytes.TrimRight(out, "\r\n"), bytes.TrimRight(want, "\r\n")) {
		return fmt.Errorf("--indent 1 形态不符:\n%q", out)
	}
	return nil
}

// odash-stdout-channel（#12）：-o - 恒走 stdout——证红锚：修复前
// `build x -o -` 落盘名为 '-' 的文件且 stdout 空。字节契约走二进制
// 通道（无 CRLF 改写），且不打落盘类 hint。
func caseOdashStdout(exe, dir string) error {
	writeFile(dir, "o.json.mbt", "struct S {\n  a : Int\n}\npub let o : S = S::{ a: 1 }\n")
	rc, out, stderr, err := runExe(exe, dir, "build", "o.json.mbt", "-o", "-")
	if err != nil {
		return err
	}
	if rc != 0 {
		return fmt.Errorf("build -o - rc = %d, want 0 (stderr=%q)", rc, stderr)
	}
	want := []byte("{\"a\":1}\n")
	if !bytes.Equal(out, want) {
		return fmt.Errorf("stdout 逐字节不符: want %q got %q", want, out)
	}
	if _, err := os.Stat(filepath.Join(dir, "-")); err == nil {
		return fmt.Errorf("不应落盘名为 '-' 的文件（#12 修复前行为）")
	}
	if strings.Contains(string(stderr), "hint:") {
		return fmt.Errorf("stdout 通道不应打落盘类 hint, got %q", stderr)
	}
	// import 对称：-o - 出 .mbt 文本，不落盘
	writeFile(dir, "p.json", "{\"k\": 1}\n")
	rc, out, stderr, err = runExe(exe, dir, "import", "p.json", "-o", "-")
	if err != nil || rc != 0 {
		return fmt.Errorf("import -o - rc=%d err=%v stderr=%q", rc, err, stderr)
	}
	if !bytes.Contains(out, []byte("pub let p")) {
		return fmt.Errorf("import -o - stdout 应含产物绑定 pub let p, got %q", out)
	}
	if _, err := os.Stat(filepath.Join(dir, "p.json.mbt")); err == nil {
		return fmt.Errorf("import -o - 不应落盘 p.json.mbt")
	}
	return nil
}

// odash-exclusive（#12）：-o - 与 --check/--fmt 互斥（盘面语义无目标）、
// stdin→stdout 无 stem 来源——全部 J0001 rc 4 fail loud。
func caseOdashExclusive(exe, dir string) error {
	writeFile(dir, "q.json", "{\"k\": 1}\n")
	for _, args := range [][]string{
		{"import", "q.json", "-o", "-", "--check"},
		{"import", "q.json", "-o", "-", "--fmt"},
	} {
		rc, _, stderr, err := runExe(exe, dir, args...)
		if err != nil {
			return err
		}
		if rc != 4 {
			return fmt.Errorf("args=%v rc = %d, want 4", args, rc)
		}
		if !bytes.Contains(stderr, []byte("[J0001]")) {
			return fmt.Errorf("args=%v 应报 J0001, got %q", args, stderr)
		}
	}
	rc, _, stderr, err := runExeWithStdin(exe, dir, "{\"k\":1}", "import", "-", "-o", "-")
	if err != nil {
		return err
	}
	if rc != 4 || !bytes.Contains(stderr, []byte("[J0001]")) {
		return fmt.Errorf("stdin→stdout 应 J0001 rc4, got rc=%d stderr=%q", rc, stderr)
	}
	return nil
}

// fmt-fail-j0002（#12）：moon fmt 失败 → rc=4 + 成因多因列举文案 + help
// 行声明半成功态 + 未 fmt 产物保留。driver 临时目录在仓外系统 Temp：
// moon 在场则 fmt 报 not-in-workspace（真·盲区），moon 缺席则 spawn 失败
// ——两种成因都必须走同一 J0002 出口（断言成因不敏感）。
func caseFmtFailJ0002(exe, dir string) error {
	writeFile(dir, "f.json", "{\"k\": 1}\n")
	rc, _, stderr, err := runExe(exe, dir, "import", "f.json", "--fmt", "-o", "f.json.mbt")
	if err != nil {
		return err
	}
	if rc != 4 {
		return fmt.Errorf("fmt 失败 rc = %d, want 4（rc 契约——#12 实测 4，正文误报 0）", rc)
	}
	for _, frag := range []string{"[J0002]", "outside any moon workspace", "help:"} {
		if !bytes.Contains(stderr, []byte(frag)) {
			return fmt.Errorf("stderr 应含 %q（多因文案/help 半成功态声明）, got %q", frag, stderr)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "f.json.mbt")); err != nil {
		return fmt.Errorf("fmt 失败后未 fmt 产物应保留（半成功态契约）: %v", err)
	}
	return nil
}

// reserved-field-roundtrip：#13 红→绿锚。保留字字段名 where + 异类型兄弟
// 字段：修复前 import 整对象退 Map、值统一失败 → 误导性 J4011 rc 1；
// 修复后 struct 照出（where 改名 where_ + field-alias 注记），build 按注记
// 还原 JSON 键，整链字节等价。
func caseReservedFieldRoundtrip(exe, dir string) error {
	json := `{"a": [{"where": "x", "b": ["t"]}]}`
	writeFile(dir, "w.json", json)
	rc, _, _, err := runExe(exe, dir, "import", "w.json", "-o", "w.json.mbt")
	if err != nil {
		return err
	}
	if rc != 0 {
		return fmt.Errorf("import rc = %d, want 0 (#13 修复前为 J4011 rc 1)", rc)
	}
	prod, err := os.ReadFile(filepath.Join(dir, "w.json.mbt"))
	if err != nil {
		return err
	}
	for _, want := range []string{
		"// jsonmbt: field-alias Where.where_ = \"where\"",
		"where_ : String",
		"Where::{ where_: \"x\", b: [\"t\"] }",
	} {
		if !strings.Contains(string(prod), want) {
			return fmt.Errorf("产物缺 %q:\n%s", want, prod)
		}
	}
	// build 就地写同名 .json：键按注记还原（where_ → where），紧凑字节等价
	if rc, _, _, err := runExe(exe, dir, "build", "w.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v", rc, err)
	}
	got, err := os.ReadFile(filepath.Join(dir, "w.json"))
	if err != nil {
		return err
	}
	want := []byte(`{"a":[{"where":"x","b":["t"]}]}`)
	if !bytes.Equal(bytes.TrimRight(got, "\r\n"), want) {
		return fmt.Errorf("round-trip 键还原失败\n--want--\n%q\n--got--\n%q", want, got)
	}
	return nil
}

// j4010-container-grouping：#14-3 红→绿锚。顶层 doc/嵌套 schema 单样本
// 不再与数组元素键集混计——报告按容器路径分组（golden 逐字节）。
func caseJ4010ContainerGrouping(exe, dir string) error {
	writeFile(dir, "e.json",
		`{"doc": {"schema": 1}, "entries": [{"a": 1, "b": 2}, {"a": 1, "c": 3}]}`)
	rc, _, stderr, err := runExe(exe, dir, "import", "e.json", "-o", "e.json.mbt")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1", rc)
	}
	want := []byte("jsonmbt: error [J4010] e.json:1:1 incompatible object shapes across samples (D-5 key-set drift): at $.entries[]: 2 distinct key sets in 2 samples: ×1 { a, b }; ×1 { a, c }\n" +
		"  help: key-set drift is not auto-converted — hand-model each key set as an enum variant (D-5), or make the samples uniform; counts cover samples seen up to the first conflicting merge (the scan stops there), so treat them as lower bounds\n")
	if !bytes.Equal(stderr, want) {
		return fmt.Errorf("stderr 逐字节不符（#14-3 分组文案）：\n--want--\n%q\n--got--\n%q", want, stderr)
	}
	return nil
}

// j4011-map-escape-cause：#13 文案红→绿锚。不可改名键（点号）走 Map 逃生门
// 失败时须点名键因（修复前报跨样本类型冲突的误导文案）。
func caseJ4011MapEscapeCause(exe, dir string) error {
	writeFile(dir, "d.json", `{"a.b": "x", "c": ["t"]}`)
	rc, _, stderr, err := runExe(exe, dir, "import", "d.json", "-o", "d.json.mbt")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1", rc)
	}
	want := []byte("jsonmbt: error [J4011] d.json:1:1 cannot unify values under keys that are not legal MoonBit field labels ('a.b'): String vs Array[String]\n" +
		"  help: these keys force Map degradation (heterogeneous values cannot unify) — rename the keys in the JSON, or hand-write a struct\n")
	if !bytes.Equal(stderr, want) {
		return fmt.Errorf("stderr 逐字节不符（#13 键因文案）：\n--want--\n%q\n--got--\n%q", want, stderr)
	}
	return nil
}

// j3009-alias-gate：field-alias 注记的门禁锚。合法注记 → build 还原键；
// 指向不存在字段的注记 → J3009（fail loud，不静默忽略）。
func caseJ3009AliasGate(exe, dir string) error {
	ok := "// jsonmbt: field-alias Rule.where_ = \"where\"\n" +
		"struct Rule {\n  where_ : String\n}\n" +
		"pub let r : Rule = Rule::{ where_: \"x\" }\n"
	rc, out, _, err := runExeWithStdin(exe, dir, ok, "build", "-")
	if err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v", rc, err)
	}
	if want := []byte(`{"where":"x"}`); !bytes.Equal(bytes.TrimRight(out, "\r\n"), want) {
		return fmt.Errorf("alias 键还原失败\n--want--\n%q\n--got--\n%q", want, out)
	}
	bad := strings.Replace(ok, "Rule.where_", "Rule.nope_", 1)
	rc, _, stderr, err := runExeWithStdin(exe, dir, bad, "check", "-")
	if err != nil {
		return err
	}
	if rc != 1 || !bytes.Contains(stderr, []byte("[J3009]")) {
		return fmt.Errorf("J3009 门禁未红：rc=%d stderr=%q", rc, stderr)
	}
	return nil
}

// doctor 子命令四用例（issue #5 验收清单逐条映射）：只读诊断「.json.mbt
// 有没有真正接上 MoonBit 工具链」。修复前（无 doctor）unknown command
// rc 4 → 全红；验收 = ❌ 挡住 + 修复行 / 撞名 ❌ / 完整接入无 ❌ / 全程只读。
func doctorFile(name, structs, binding string) string {
	return "///|\npub struct " + structs + " {\n  v : Int\n}\n\n///|\npub let " + binding + " : " + structs + " = " + structs + "::{\n  v: 1,\n}\n"
}

func caseDoctorNoPkg(exe, dir string) error {
	// 验收 1：未接 moon.pkg 的目录 → ❌ + 一行修复
	writeFile(dir, "w.json.mbt", doctorFile("W", "W", "w"))
	rc, out, _, err := runExe(exe, dir, "doctor", ".")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1 (无 moon.pkg 必须挡住)", rc)
	}
	for _, frag := range []string{"❌ package boundary", "moon.pkg"} {
		if !strings.Contains(string(out), frag) {
			return fmt.Errorf("stdout 缺 %q:\n%s", frag, out)
		}
	}
	return nil
}

func caseDoctorDupStruct(exe, dir string) error {
	// 验收 2：同目录两张含同名 struct 的 .json.mbt → ❌ 指名（moon 编译期
	// 才炸的坑，doctor 提前拦——单文件各自合法，check/build 项不背锅）
	writeFile(dir, "a.json.mbt", doctorFile("Shared", "Shared", "a"))
	writeFile(dir, "b.json.mbt", doctorFile("B", "Shared", "b"))
	rc, out, _, err := runExe(exe, dir, "doctor", ".")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1 (跨文件撞名必须挡住)", rc)
	}
	for _, frag := range []string{"❌ struct names", "Shared", "a.json.mbt", "b.json.mbt"} {
		if !strings.Contains(string(out), frag) {
			return fmt.Errorf("stdout 缺 %q:\n%s", frag, out)
		}
	}
	return nil
}

func caseDoctorClean(exe, dir string) error {
	// 验收 3：完整接入（模块根 + moon.pkg + 合法文件）→ 无 ❌（fmt 项随
	// 环境可能 ⚠️，断言不含 ❌——CI 无 moon 时不误报）
	writeFile(dir, "moon.mod", "name = \"probe/clean\"\nversion = \"0.1.0\"\n")
	writeFile(dir, "moon.pkg", "")
	writeFile(dir, "c.json.mbt", doctorFile("C", "C", "c"))
	rc, out, _, err := runExe(exe, dir, "doctor", ".")
	if err != nil {
		return err
	}
	if rc != 0 {
		return fmt.Errorf("rc = %d, want 0 (完整接入全绿)\n%s", rc, out)
	}
	if strings.Contains(string(out), "❌") {
		return fmt.Errorf("完整接入不得出现 ❌:\n%s", out)
	}
	if !strings.Contains(string(out), "✅ package boundary") {
		return fmt.Errorf("缺 ✅ package boundary:\n%s", out)
	}
	return nil
}

func caseDoctorReadonly(exe, dir string) error {
	// 验收 4：全程只读——跑前后目录快照（文件集 + 内容）逐字节不变
	writeFile(dir, "w.json.mbt", doctorFile("W", "W", "w"))
	snap := func() map[string]string {
		m := map[string]string{}
		entries, _ := os.ReadDir(dir)
		for _, e := range entries {
			if b, err := os.ReadFile(filepath.Join(dir, e.Name())); err == nil {
				m[e.Name()] = string(b)
			}
		}
		return m
	}
	before := snap()
	if _, _, _, err := runExe(exe, dir, "doctor", "."); err != nil {
		return err
	}
	after := snap()
	if len(before) != len(after) {
		return fmt.Errorf("doctor 产生/删除了文件: before=%v after=%v", before, after)
	}
	for k, v := range before {
		if after[k] != v {
			return fmt.Errorf("doctor 改写了 %s", k)
		}
	}
	return nil
}

// type-name-map（#6-4）：机器派生名 → 语义名映射全链。层 1 已锚语义；
// 此处锚 CLI 进程面：flag 解析、映射文件读取与校验（J1010/J1002）、
// 未命中键 hint（不阻断）、Map 值宿主键派生命名（CasesEntry）。
func caseTypeNameMap(exe, dir string) error {
	writeFile(dir, "items.json", `{"items": [{"id": 1, "file": "x"}]}`)
	writeFile(dir, "map.json", `{"Id": "Entry"}`)
	rc, _, _, err := runExe(exe, dir, "import", "items.json", "--type-name-map", "map.json", "-o", "items.json.mbt")
	if err != nil || rc != 0 {
		return fmt.Errorf("import rc=%d err=%v", rc, err)
	}
	prod, _ := os.ReadFile(filepath.Join(dir, "items.json.mbt"))
	s := string(prod)
	if !strings.Contains(s, "pub struct Entry") || strings.Contains(s, "pub struct Id") {
		return fmt.Errorf("映射未生效：\n%s", s)
	}
	if !strings.Contains(s, `Entry::{ id: 1, file: "x" }`) {
		return fmt.Errorf("数据引用未随映射更新：\n%s", s)
	}
	// 往返
	if rc, _, _, err := runExe(exe, dir, "build", "items.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v", rc, err)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "items.json"))
	if want := []byte(`{"items":[{"id":1,"file":"x"}]}`); !bytes.Equal(bytes.TrimRight(got, "\r\n"), want) {
		return fmt.Errorf("round-trip 失败\n--want--\n%q\n--got--\n%q", want, got)
	}
	// 值非法（小写）→ J1010 rc 1
	writeFile(dir, "bad1.json", `{"Id": "entry"}`)
	if rc, _, stderr, _ := runExe(exe, dir, "import", "items.json", "--type-name-map", "bad1.json", "-o", "x.mbt"); rc != 1 || !bytes.Contains(stderr, []byte("[J1010]")) {
		return fmt.Errorf("非法值应 J1010 rc1: rc=%d stderr=%q", rc, stderr)
	}
	// 形态错（数组）→ J1010 rc 1
	writeFile(dir, "bad2.json", `[1,2]`)
	if rc, _, stderr, _ := runExe(exe, dir, "import", "items.json", "--type-name-map", "bad2.json", "-o", "x.mbt"); rc != 1 || !bytes.Contains(stderr, []byte("[J1010]")) {
		return fmt.Errorf("数组形态应 J1010 rc1: rc=%d stderr=%q", rc, stderr)
	}
	// 未命中键 → hint 不阻断（rc 0）
	writeFile(dir, "unmatch.json", `{"Nope": "X"}`)
	if rc, _, stderr, _ := runExe(exe, dir, "import", "items.json", "--type-name-map", "unmatch.json", "-o", "x2.mbt"); rc != 0 {
		return fmt.Errorf("未命中应 rc0: rc=%d stderr=%q", rc, stderr)
	}
	// Map 值宿主键派生（#6-4 评论拍板）：cases 值 → CasesEntry（旧 = Src_sha 首键误导）
	writeFile(dir, "digest.json", `{"cases": {"a.c": {"src_sha": "s1", "exit_code": 0}, "b.c": {"src_sha": "s2", "exit_code": 1}}}`)
	if rc, _, _, err := runExe(exe, dir, "import", "digest.json", "-o", "digest.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("digest import rc=%d err=%v", rc, err)
	}
	d, _ := os.ReadFile(filepath.Join(dir, "digest.json.mbt"))
	if !strings.Contains(string(d), "Map[String, CasesEntry]") || strings.Contains(string(d), "Src_sha") {
		return fmt.Errorf("Map 值命名未用宿主派生：\n%s", d)
	}
	return nil
}

// #23：--type-name-map 命中后派生名须占位——同文件「异签名、同基名」的组，
// 第 2 个组不得再算出同一个 derived、再命中同一条映射而假撞名。
// 实测形态 = MoUI checks/linux.json（sourceBuild 与 rendererL2 基名均 Status）。
// 层 1 已锚语义；此处锚 CLI 进程面：rc 0、两名并存、往返等价。
func caseNameMapRepeatedBase(exe, dir string) error {
	// a 与 b 首键同为 status、键集不同 → 两个签名（Status / Status2）
	writeFile(dir, "plat.json", `{"a":{"status":1,"evidence":2},"b":{"status":1,"route":2}}`)
	// 首轮（-o -，不落盘，避免产物进入 taken 扫描面）确认未映射序列
	rc, out, _, err := runExe(exe, dir, "import", "plat.json", "-o", "-")
	if err != nil || rc != 0 {
		return fmt.Errorf("首轮 rc=%d err=%v", rc, err)
	}
	if !strings.Contains(string(out), "Status2") {
		return fmt.Errorf("未映射序列缺 Status2:\n%s", string(out))
	}
	// 带 map：只替换 Status → Foo；Status2 须保持（修前 = J1010 假撞名）
	writeFile(dir, "m.json", `{"Status":"Foo"}`)
	rc, _, stderr, err := runExe(exe, dir, "import", "plat.json", "--type-name-map", "m.json", "-o", "plat.json.mbt")
	if err != nil || rc != 0 {
		return fmt.Errorf("#23 假撞名：rc=%d stderr=%q", rc, stderr)
	}
	prod, _ := os.ReadFile(filepath.Join(dir, "plat.json.mbt"))
	s := string(prod)
	if !strings.Contains(s, "pub struct Foo") || !strings.Contains(s, "pub struct Status2") {
		return fmt.Errorf("映射结果不符（期望 Foo + Status2）:\n%s", s)
	}
	// 往返等价
	if rc, _, _, err := runExe(exe, dir, "build", "plat.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v", rc, err)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "plat.json"))
	want := `{"a":{"status":1,"evidence":2},"b":{"status":1,"route":2}}`
	if strings.TrimRight(string(got), "\r\n") != want {
		return fmt.Errorf("round-trip\nwant=%s\ngot =%s", want, string(got))
	}
	return nil
}

// #24：跨文件 taken 参与 dedup 兜底——同目录第二文件的异签名组在 stem 前缀
// 也被占后，不得退回未前缀的 taken 名（否则 moon [4051] 声明两次）。
// 实测形态 = MoUI 同目录多文件同基名组。
func caseCrossFileTakenDedup(exe, dir string) error {
	writeFile(dir, "a.json", `{"k":"a","one":{"status":1,"evidence":2},"two":{"status":1,"route":2}}`)
	writeFile(dir, "b.json", `{"k":"b","one":{"status":1,"evidence":2},"two":{"status":1,"route":2}}`)
	if rc, _, _, err := runExe(exe, dir, "import", "a.json"); err != nil || rc != 0 {
		return fmt.Errorf("a import rc=%d err=%v", rc, err)
	}
	if rc, _, _, err := runExe(exe, dir, "import", "b.json"); err != nil || rc != 0 {
		return fmt.Errorf("b import rc=%d err=%v", rc, err)
	}
	b, _ := os.ReadFile(filepath.Join(dir, "b.json.mbt"))
	s := string(b)
	if !strings.Contains(s, "pub struct BStatus") || !strings.Contains(s, "pub struct Status3") {
		return fmt.Errorf("b 未按 taken 选名（期望 BStatus + Status3）:\n%s", s)
	}
	if strings.Contains(s, "pub struct Status {") {
		return fmt.Errorf("b 复用 taken 裸名 Status（moon [4051] 隐患）:\n%s", s)
	}
	return nil
}


// migrate 子命令（#6-5）：批量迁移侦察三榜报告——byte-eq（可直进 CI 对账）/
// value-eq（值等仅风格差，确认口径）/ reject（带 J 码原因）；默认零写
// （--write 才落盘）；同目录撞名触发 stem 前缀化时告警指向 --type-name-map。
func caseMigrate(exe, dir string) error {
	// byte-eq（pretty）：2 空格缩进原文件 = build --pretty 逐字节
	writeFile(dir, "cfg.json", "{\n  \"port\": 8080,\n  \"host\": \"localhost\"\n}")
	// value-eq：1 空格缩进（风格差——值等键序同）
	writeFile(dir, "style.json", "{\n \"a\": 1,\n \"b\": [2, 3]\n}")
	// reject：异构数组
	writeFile(dir, "bad.json", `{"rows": [1, "a"]}`)
	rc, out, _, err := runExe(exe, dir, "migrate", ".")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1 (有 reject)", rc)
	}
	s := string(out)
	for _, frag := range []string{
		"cfg.json", "BYTE-EQ",
		"style.json", "VALUE-EQ",
		"bad.json", "REJECT", "[J4010]",
		"summary: 3 file(s): 1 byte-eq, 1 value-eq, 1 reject",
	} {
		if !strings.Contains(s, frag) {
			return fmt.Errorf("报告缺 %q:\n%s", frag, s)
		}
	}
	// 默认零写：没有任何 .json.mbt 落盘
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if strings.HasSuffix(e.Name(), ".json.mbt") {
			return fmt.Errorf("默认模式不得写盘，发现 %s", e.Name())
		}
	}
	// --write：非 reject 落盘（cfg/style 两张）
	if rc, _, _, err := runExe(exe, dir, "migrate", ".", "--write"); err != nil || rc != 1 {
		return fmt.Errorf("--write rc=%d err=%v（reject 仍在，rc 1）", rc, err)
	}
	for _, name := range []string{"cfg.json.mbt", "style.json.mbt"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			return fmt.Errorf("--write 未落盘 %s: %v", name, err)
		}
	}
	if _, err := os.Stat(filepath.Join(dir, "bad.json.mbt")); err == nil {
		return fmt.Errorf("reject 文件不得落盘 bad.json.mbt")
	}
	// 无 json 目录：rc 0 + 提示
	sub := filepath.Join(dir, "empty")
	os.MkdirAll(sub, 0o755)
	if rc, out2, _, err := runExe(exe, dir, "migrate", "empty"); err != nil || rc != 0 || !strings.Contains(string(out2), "no .json") {
		return fmt.Errorf("空目录应 rc0 + 提示: rc=%d out=%q err=%v", rc, out2, err)
	}
	return nil
}

// j2007-help-text（#15）：help 文案与实现对齐锚——Option 的合法写法是
// 后缀糖 T?（Option[Int] 前缀形态被 parse 判 JTUnsupported 拒收），文案
// 必须指路真实语法，逐字节 golden。
func caseJ2007HelpText(exe, dir string) error {
	writeFile(dir, "s.json.mbt", "struct S {\n  n : Option[Int]\n}\npub let s : S = S::{ n: None }\n")
	rc, _, stderr, err := runExe(exe, dir, "check", "s.json.mbt")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("rc = %d, want 1", rc)
	}
	want := []byte("jsonmbt: error [J2007] s.json.mbt:2:3 field type is outside the L0 subset\n" +
		"  help: supported field types: Int/Int64/Double/String/Bool/T? (Option)/Array[T]/Map[String,T]/struct\n")
	if !bytes.Equal(stderr, want) {
		return fmt.Errorf("stderr 逐字节不符（#15 文案对齐）：\n--want--\n%q\n--got--\n%q", want, stderr)
	}
	// #14 批次1：嵌套 Option（T??）收窄——静默压平（None 与 Some(None) 同降
	// null）是无损红线违例，J2007 fail loud（递归拒任意深度；纯手写面）
	writeFile(dir, "q.json.mbt", "struct S {\n  a : String??\n}\npub let q : S = S::{ a: None }\n")
	rc, _, stderr, err = runExe(exe, dir, "check", "q.json.mbt")
	if err != nil {
		return err
	}
	if rc != 1 {
		return fmt.Errorf("T?? rc = %d, want 1", rc)
	}
	want2 := []byte("jsonmbt: error [J2007] q.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n" +
		"  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then\n")
	if !bytes.Equal(stderr, want2) {
		return fmt.Errorf("T?? stderr 逐字节不符：\n--want--\n%q\n--got--\n%q", want2, stderr)
	}
	return nil
}

// migrate-taken-twins（审阅 P2）：目录已有 .json.mbt 孪生时 taken 必须
// 预扫纳入盘面 struct 名——修复前 taken=[] 起始，b.json 判 Id 不前缀化、
// --write 产物与真实 import 不一致 → import --check rc=2 自相矛盾。
func caseMigrateTakenTwins(exe, dir string) error {
	// 已迁移产物（含 Id——b.json 的数组元素组也派生 Id → 真实 import 前缀化 BId）
	writeFile(dir, "a.json.mbt", "pub struct Id {\n  id : Int\n}\n\npub let a : Id = Id::{\n  id: 1,\n}\n")
	writeFile(dir, "b.json", `{"items": [{"id": 2}]}`)
	// 侦察报告须含前缀化告警（模拟真实迁移的撞名序列）
	rc, out, _, err := runExe(exe, dir, "migrate", ".")
	if err != nil {
		return err
	}
	if rc != 0 {
		return fmt.Errorf("rc = %d, want 0", rc)
	}
	if !strings.Contains(string(out), "stem-prefixed") || !strings.Contains(string(out), "BId") {
		return fmt.Errorf("应报前缀化告警 BId（taken 预扫失真则无告警）:\n%s", out)
	}
	// --write 落盘产物必须与真实 import 一致（自洽闸：import --check rc=0）
	if rc, _, _, err := runExe(exe, dir, "migrate", ".", "--write"); err != nil || rc != 0 {
		return fmt.Errorf("--write rc=%d err=%v", rc, err)
	}
	if rc, _, stderr, err := runExe(exe, dir, "import", "b.json", "--check"); err != nil || rc != 0 {
		return fmt.Errorf("自洽闸：migrate --write 产物应与 import 一致（--check rc=%d）\nstderr=%q err=%v", rc, stderr, err)
	}
	prod, _ := os.ReadFile(filepath.Join(dir, "b.json.mbt"))
	if !strings.Contains(string(prod), "pub struct BId") {
		return fmt.Errorf("产物应为前缀化形态 BId:\n%s", prod)
	}
	return nil
}

// never-placeholder（#14-2a）：空容器默认 Never 底型占位——J4001/J4002 不再
// 整张拒（--strict 恢复旧拒）；产物含 enum Never 定义 + 往返字节等价；
// 冻结分支口径：孤空容器 REJECT 的 ~99% 场景直接可用。
func caseNeverPlaceholder(exe, dir string) error {
	writeFile(dir, "e.json", `{"exemptions": []}`)
	rc, _, stderr, err := runExe(exe, dir, "import", "e.json", "-o", "e.json.mbt")
	if err != nil || rc != 0 {
		return fmt.Errorf("import rc=%d err=%v stderr=%q", rc, err, stderr)
	}
	prod, _ := os.ReadFile(filepath.Join(dir, "e.json.mbt"))
	for _, frag := range []string{"pub enum Never {}", "exemptions : Array[Never]", "exemptions: []"} {
		if !strings.Contains(string(prod), frag) {
			return fmt.Errorf("产物缺 %q:\n%s", frag, prod)
		}
	}
	if !strings.Contains(string(stderr), "J4031") {
		return fmt.Errorf("应给 J4031 占位 hint: stderr=%q", stderr)
	}
	// 往返字节等价
	if rc, _, _, err := runExe(exe, dir, "build", "e.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("build rc=%d err=%v", rc, err)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "e.json"))
	if want := []byte(`{"exemptions":[]}`); !bytes.Equal(bytes.TrimRight(got, "\r\n"), want) {
		return fmt.Errorf("往返不等\n--want--\n%q\n--got--\n%q", want, got)
	}
	// --strict 恢复旧拒（rc 1 J4001）
	if rc, _, stderr, _ := runExe(exe, dir, "import", "e.json", "--strict", "-o", "x.mbt"); rc != 1 || !bytes.Contains(stderr, []byte("[J4001]")) {
		return fmt.Errorf("--strict 应 J4001 rc1: rc=%d stderr=%q", rc, stderr)
	}
	// 空对象同机制（Map[String, Never]）
	writeFile(dir, "o.json", `{"cfg": {}}`)
	if rc, _, _, err := runExe(exe, dir, "import", "o.json", "-o", "o.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("空对象 import rc=%d err=%v", rc, err)
	}
	o, _ := os.ReadFile(filepath.Join(dir, "o.json.mbt"))
	if !strings.Contains(string(o), "Map[String, Never]") {
		return fmt.Errorf("空对象应 Map[String,Never]:\n%s", o)
	}
	return nil
}

// fill（#14-2b）：按已声明类型重算值体——头逐字节保留、键集漂移按声明
// enum 消歧（tag/键集双形态）、--fill --check 分档闸（源变 rc2）、互斥拒。
func caseFill(exe, dir string) error {
	writeFile(dir, "t.json.mbt", "enum Case {\n  A(Ax)\n  B(Bx)\n}\nstruct Ax {\n  a : Int\n}\nstruct Bx {\n  b : Int\n}\nstruct T {\n  xs : Array[Case]\n}\n\n// hand-renamed header comment must survive\npub let t : T = T::{\n  xs: [],\n}\n")
	writeFile(dir, "t.json", `{"xs": [{"a": 1}, {"b": 2}]}`)
	if rc, _, _, err := runExe(exe, dir, "import", "t.json", "--fill", "t.json.mbt"); err != nil || rc != 0 {
		return fmt.Errorf("fill rc=%d err=%v", rc, err)
	}
	got, _ := os.ReadFile(filepath.Join(dir, "t.json.mbt"))
	s := string(got)
	// 头逐字节保留（人工注释存活）+ 消歧值体
	if !strings.Contains(s, "// hand-renamed header comment must survive") {
		return fmt.Errorf("头部人工内容丢失:\n%s", s)
	}
	if !strings.Contains(s, "A(Ax::{ a: 1 }),") || !strings.Contains(s, "B(Bx::{ b: 2 }),") {
		return fmt.Errorf("消歧值体缺失:\n%s", s)
	}
	// 同步 → check rc0
	if rc, _, _, err := runExe(exe, dir, "import", "t.json", "--fill", "t.json.mbt", "--check"); err != nil || rc != 0 {
		return fmt.Errorf("--check 同步应 rc0: rc=%d err=%v", rc, err)
	}
	// 源变 → rc2 J5001（分档闸有牙）
	writeFile(dir, "t.json", `{"xs": [{"a": 9}]}`)
	if rc, _, stderr, _ := runExe(exe, dir, "import", "t.json", "--fill", "t.json.mbt", "--check"); rc != 2 || !bytes.Contains(stderr, []byte("[J5001]")) {
		return fmt.Errorf("源变应 rc2 J5001: rc=%d stderr=%q", rc, stderr)
	}
	// tag 形态输入（fill 吃自身降级产物）+ -o - 预览
	writeFile(dir, "t.json", `{"xs": [{"case": "B", "b": 7}]}`)
	rc, out, _, err := runExe(exe, dir, "import", "t.json", "--fill", "t.json.mbt", "-o", "-")
	if err != nil || rc != 0 {
		return fmt.Errorf("预览 rc=%d err=%v", rc, err)
	}
	if !strings.Contains(string(out), "B(Bx::{ b: 7 })") {
		return fmt.Errorf("tag 消歧预览缺失:\n%s", out)
	}
	// 互斥：--fill + --type-name-map → J0001
	writeFile(dir, "m.json", `{"Id":"X"}`)
	writeFile(dir, "t.json", `{"xs": []}`)
	if rc, _, stderr, _ := runExe(exe, dir, "import", "t.json", "--fill", "t.json.mbt", "--type-name-map", "m.json"); rc != 4 || !bytes.Contains(stderr, []byte("[J0001]")) {
		return fmt.Errorf("互斥应 J0001 rc4: rc=%d stderr=%q", rc, stderr)
	}
	return nil
}

// caseMigrateAstralBytes：issue #21 红→绿锚。
// migrate 的 trim_trailing_nl 曾用 String::length()（UTF-16 码元数）索引
// to_array()（码点数）——含星面字符（emoji U+1F680）时前者更大 →
// chars[end-1] 越界 panic，且 panic 中断整批扫描（不是跳过该文件）。
// 修复前：stderr 出 PanicError 且后续文件全部缺席；修复后：三张全获判定。
func caseMigrateAstralBytes(exe, dir string) error {
	writeFile(dir, "emoji.json", "{\"a\":\"\U0001F680\"}\n")
	writeFile(dir, "ok.json", "{\"a\":1}\n")
	writeFile(dir, "bad.json", "{oops")
	rc, out, stderr, err := runExe(exe, dir, "migrate", ".")
	if err != nil {
		return fmt.Errorf("migrate 执行失败: %v", err)
	}
	// rc 契约（对齐 caseMigrate）：有 REJECT 即 rc=1；4 才是用法/IO 错
	if rc != 1 {
		return fmt.Errorf("migrate 含 1 张 REJECT 应 rc=1，实得 rc=%d\nstdout=%s\nstderr=%s", rc, out, stderr)
	}
	if bytes.Contains(stderr, []byte("PanicError")) || bytes.Contains(out, []byte("PanicError")) {
		return fmt.Errorf("migrate 遇星面字符 panic（#21 未修）\nstdout=%s\nstderr=%s", out, stderr)
	}
	// panic 会截断报告——三张都必须在 = 「单文件失败不中断整批」的探针
	for _, f := range []string{"emoji.json", "ok.json", "bad.json"} {
		if !bytes.Contains(out, []byte(f)) {
			return fmt.Errorf("migrate 报告缺 %s（整批被中断？）\nstdout=%s", f, out)
		}
	}
	// 星面字符的字符串照常定型并获 BYTE-EQ 判定（不是降级成"跳过"）
	if !bytes.Contains(out, []byte("emoji.json → BYTE-EQ")) {
		return fmt.Errorf("emoji.json 未获 BYTE-EQ 判定\nstdout=%s", out)
	}
	if !bytes.Contains(out, []byte("bad.json → REJECT")) {
		return fmt.Errorf("bad.json 未获 REJECT 判定（坏文件应只让自己失败）\nstdout=%s", out)
	}
	return nil
}

var cases = []testCase{
	{"J2003-emdash-stderr-bytes", caseEmdashStderr},
	{"migrate-astral-bytes", caseMigrateAstralBytes},
	{"probe-samples-golden", caseProbeSamples},
	{"build-stdout-deterministic", caseBuildDeterministic},
	{"import-check-idempotent", caseImportCheckGate},
	{"usage-rc4", caseUsageRC4},
	{"pretty-vs-go-encoder", casePrettyVsGoEncoder},
	{"pretty-key-order", casePrettyKeyOrder},
	{"stderr-line-contract", caseStderrLineContract},
	{"cli-hints", caseCliHints},
	{"odash-stdout-channel", caseOdashStdout},
	{"odash-exclusive", caseOdashExclusive},
	{"fmt-fail-j0002", caseFmtFailJ0002},
	{"reserved-field-roundtrip", caseReservedFieldRoundtrip},
	{"j4010-container-grouping", caseJ4010ContainerGrouping},
	{"j4011-map-escape-cause", caseJ4011MapEscapeCause},
	{"j3009-alias-gate", caseJ3009AliasGate},
	{"doctor-no-pkg", caseDoctorNoPkg},
	{"doctor-dup-struct", caseDoctorDupStruct},
	{"doctor-clean", caseDoctorClean},
	{"doctor-readonly", caseDoctorReadonly},
	{"type-name-map", caseTypeNameMap},
	{"name-map-repeated-base", caseNameMapRepeatedBase},
	{"cross-file-taken-dedup", caseCrossFileTakenDedup},
	{"migrate-three-boards", caseMigrate},
	{"j2007-help-text", caseJ2007HelpText},
	{"migrate-taken-twins", caseMigrateTakenTwins},
	{"never-placeholder", caseNeverPlaceholder},
	{"fill", caseFill},
}

func defaultExe() string {
	cands := []string{
		filepath.Join("_build", "native", "debug", "build", "cmd", "jsonmbt", "jsonmbt.exe"),
		filepath.Join("_build", "native", "release", "build", "cmd", "jsonmbt", "jsonmbt.exe"),
	}
	if runtime.GOOS != "windows" {
		cands = append(cands,
			filepath.Join("_build", "native", "debug", "build", "cmd", "jsonmbt", "jsonmbt"))
	}
	for _, c := range cands {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			abs, _ := filepath.Abs(c)
			return abs
		}
	}
	return ""
}

func main() {
	flag.Parse()
	exe := *exePath
	if exe == "" {
		exe = defaultExe()
	}
	if exe == "" {
		fmt.Fprintln(os.Stderr, "jsonmbt exe 未找到：先 MOON_CC=clang moon build --target native cmd/jsonmbt，或用 -exe 指定")
		os.Exit(2)
	}
	// 用例各自把子进程工作目录切到临时目录（cmd.Dir = dir），若此处是相对路径，
	// 子进程会相对临时目录解析 exe → 全量 fork/exec 失败（CI 曾由此 5/5 全红）。
	// 防线不依赖调用方传对路径形态：入参一律转绝对路径。
	if abs, err := filepath.Abs(exe); err == nil {
		exe = abs
	}
	if err := exeFreshness(exe); err != nil {
		fmt.Printf("FAIL exe-freshness-gate: %v\n", err)
		os.Exit(1)
	}
	fails := 0
	for _, c := range cases {
		dir, err := os.MkdirTemp("", "jsonmbt-l2-*")
		if err != nil {
			panic(err)
		}
		err = c.run(exe, dir)
		os.RemoveAll(dir)
		if err != nil {
			fails++
			fmt.Printf("FAIL %s: %v\n", c.name, err)
		} else {
			fmt.Printf("pass %s\n", c.name)
		}
	}
	fmt.Printf("total=%d failed=%d\n", len(cases), fails)
	if fails > 0 {
		os.Exit(1)
	}
}
