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
	writeFile(dir, "g.json", "{\"k\": [1, 2], \"u\": \"http://x/y\"}\n")
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

var cases = []testCase{
	{"J2003-emdash-stderr-bytes", caseEmdashStderr},
	{"probe-samples-golden", caseProbeSamples},
	{"build-stdout-deterministic", caseBuildDeterministic},
	{"import-check-idempotent", caseImportCheckGate},
	{"usage-rc4", caseUsageRC4},
	{"pretty-vs-go-encoder", casePrettyVsGoEncoder},
	{"pretty-key-order", casePrettyKeyOrder},
	{"stderr-line-contract", caseStderrLineContract},
	{"cli-hints", caseCliHints},
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
