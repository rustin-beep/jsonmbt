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
		"  help: rename the binding (or the file) so they match — this keeps one name per document")
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

var cases = []testCase{
	{"J2003-emdash-stderr-bytes", caseEmdashStderr},
	{"probe-samples-golden", caseProbeSamples},
	{"build-stdout-deterministic", caseBuildDeterministic},
	{"import-check-idempotent", caseImportCheckGate},
	{"usage-rc4", caseUsageRC4},
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
