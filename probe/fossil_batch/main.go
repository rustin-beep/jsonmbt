// probe/fossil_batch：化石分支（Vitro frozen-oracle-snapshot，2469 张 JSON）
// 批量实验驱动——D-6 第二档 jsonmbt-go 库 × jsonmbt exe 的双实现对账：
//
//	Go Generate 产 .json.mbt → jsonmbt check → jsonmbt build → 与原 JSON
//	值语义对拍（键序 + 值）。失败首例留档供定位。
//
// 运行：go run ./probe/fossil_batch <vitro 仓> <exe> <workdir>
package main

import (
	"archive/tar"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"

	jsonmbt_go "rustin-beep/jsonmbt/l2/probe/jsonmbt_go"
)

type counter struct {
	pass         int
	genRejected  int
	checkFail    int
	buildFail    int
	mismatch     int
	rejectByKind map[string]int
	firstFails   map[string]string // 类别 → 首例描述
}

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintln(os.Stderr, "usage: go run ./probe/fossil_batch <vitro-repo> <jsonmbt.exe> <workdir> [-mode(exe-import)]")
		os.Exit(2)
	}
	repo, exe, work := os.Args[1], os.Args[2], os.Args[3]
	if err := os.MkdirAll(work, 0o755); err != nil {
		panic(err)
	}
	// 一次性解包化石分支的 JSON（git archive 最快路径）
	jsonDir := filepath.Join(work, "fossil_json")
	if _, err := os.Stat(jsonDir); os.IsNotExist(err) {
		cmd := exec.Command("git", "-C", repo, "archive", "frozen-oracle-snapshot", "golden")
		r, err := cmd.Output()
		if err != nil {
			panic(err)
		}
		if err := untar(jsonDir, bytes.NewReader(r)); err != nil {
			panic(err)
		}
	}
	var files []string
	filepath.WalkDir(jsonDir, func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.HasSuffix(p, ".json") {
			files = append(files, p)
		}
		return nil
	})
	fmt.Printf("fossil json files: %d\n", len(files))
	c := &counter{rejectByKind: map[string]int{}, firstFails: map[string]string{}}
	outDir := filepath.Join(work, "out")
	os.MkdirAll(outDir, 0o755)
	exeMode := len(os.Args) > 4 && os.Args[4] == "-mode"
	if exeMode {
		runExeImportAll(files, exe, filepath.Join(work, "out_exe"), c)
		fmt.Printf("exe-import: pass=%d rejected=%d checkFail=%d mismatch=%d\n",
			c.pass, c.genRejected, c.checkFail, c.mismatch)
		return
	}
	for _, f := range files {
		runOne(f, exe, outDir, c)
	}
	fmt.Printf("pass=%d genRejected=%d checkFail=%d buildFail=%d mismatch=%d total=%d\n",
		c.pass, c.genRejected, c.checkFail, c.buildFail, c.mismatch,
		c.pass+c.genRejected+c.checkFail+c.buildFail+c.mismatch)
	fmt.Println("reject kinds:")
	var kinds []string
	for k := range c.rejectByKind {
		kinds = append(kinds, k)
	}
	sort.Strings(kinds)
	for _, k := range kinds {
		fmt.Printf("  %-40s %d\n", k, c.rejectByKind[k])
	}
	for k, v := range c.firstFails {
		fmt.Printf("first[%s]: %s\n", k, v)
	}
}

func genWithRecover(stem, srcName string, raw []byte) (out string, err error) {
	defer func() {
		if r := recover(); r != nil {
			out, err = "", fmt.Errorf("PANIC: %v", r)
		}
	}()
	return jsonmbt_go.Generate(stem, srcName, raw)
}

func runOne(jsonPath, exe, outDir string, c *counter) {
	base := jsonmbt_go.SanitizeStem(strings.TrimSuffix(filepath.Base(jsonPath), ".json"))
	raw, err := os.ReadFile(jsonPath)
	if err != nil {
		c.note("read-fail", jsonPath+": "+err.Error())
		return
	}
	mbtText, genErr := genWithRecover(base, filepath.Base(jsonPath), raw)
	if genErr != nil {
		kind := "other"
		if strings.HasPrefix(genErr.Error(), "PANIC: ") {
			kind = "LIB-PANIC"
			c.checkFail++ // 库 panic 视同库缺陷面（不计诚实拒绝）
		} else if strings.HasPrefix(genErr.Error(), "rejected: ") {
			kind = strings.TrimSpace(strings.TrimPrefix(genErr.Error(), "rejected: "))
			kind = firstWords(kind, 6)
			c.genRejected++
		}
		c.rejectByKind[kind]++
		if _, ok := c.firstFails["gen:"+kind]; !ok {
			c.firstFails["gen:"+kind] = jsonPath + " :: " + genErr.Error()
		}
		return
	}
	mbtPath, _ := filepath.Abs(filepath.Join(outDir, base+".json.mbt"))
	if err := os.WriteFile(mbtPath, []byte(mbtText), 0o644); err != nil {
		panic(err)
	}
	// check（Go 产物必须过 jsonmbt 自家校验）
	if r, _ := run(exe, outDir, "check", mbtPath); !r.ok {
		c.checkFail++
		c.note("check-fail", jsonPath+" :: "+firstLine(r.stderr))
		return
	}
	// build 回 JSON
	rtPath, _ := filepath.Abs(filepath.Join(outDir, base+".rt.json"))
	if r, _ := run(exe, outDir, "build", mbtPath, "-o", rtPath); !r.ok {
		c.buildFail++
		c.note("build-fail", jsonPath+" :: "+firstLine(r.stderr))
		return
	}
	// 值语义对拍（Go 侧宽松数值比较：json.Number 文本不等时数值比）
	got, err1 := os.ReadFile(rtPath)
	var a, b any
	da := json.NewDecoder(bytes.NewReader(raw))
	da.UseNumber()
	db := json.NewDecoder(bytes.NewReader(got))
	db.UseNumber()
	if err1 != nil || da.Decode(&a) != nil || db.Decode(&b) != nil {
		c.mismatch++
		c.note("mismatch", jsonPath+" :: decode rt failed")
		return
	}
	if !jsonEqual(a, b) {
		c.mismatch++
		c.note("mismatch", jsonPath)
		return
	}
	c.pass++
}

// runExeImportAll：jsonmbt exe 的 import 对照批量（8 worker；产物名 = 清洗
// stem 与 binding 对齐 D-7；check + build 回 + 值对拍同 Go 路径）
func runExeImportAll(files []string, exe, outDir string, c *counter) {
	os.MkdirAll(outDir, 0o755)
	jobs := make(chan string)
	var wg sync.WaitGroup
	var mu sync.Mutex
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for f := range jobs {
				ok := func() bool {
					// 目录分桶防同名互踩（baseline/rules.json 与 parser_diff/rules.json
					// 清洗后同名——平铺并行会互相覆盖出假 mismatch）
					sub := strconv.FormatUint(uint64(hashStr(filepath.Dir(f))), 16)
					dir := filepath.Join(outDir, sub)
					os.MkdirAll(dir, 0o755)
					base := jsonmbt_go.SanitizeStem(strings.TrimSuffix(filepath.Base(f), ".json"))
					mbt := filepath.Join(dir, base+".json.mbt")
					r, _ := run(exe, "", "import", f, "-o", mbt)
					if !r.ok {
						mu.Lock()
						if strings.Contains(r.stderr, "J4") || strings.Contains(r.stderr, "J2") {
							c.genRejected++
							kind := firstWords(firstLine(r.stderr), 3)
							c.rejectByKind[kind]++
						} else {
							c.checkFail++
							c.note("exe-import-fail", f+" :: "+firstLine(r.stderr))
						}
						mu.Unlock()
						return false
					}
					if r, _ := run(exe, "", "check", mbt); !r.ok {
						mu.Lock()
						c.checkFail++
						c.note("exe-check-fail", f+" :: "+firstLine(r.stderr))
						mu.Unlock()
						return false
					}
					rt := filepath.Join(dir, base+".rt.json")
					if r, _ := run(exe, "", "build", mbt, "-o", rt); !r.ok {
						mu.Lock()
						c.buildFail++
						c.note("exe-build-fail", f+" :: "+firstLine(r.stderr))
						mu.Unlock()
						return false
					}
					raw, err1 := os.ReadFile(f)
					got, err2 := os.ReadFile(rt)
					if err1 != nil || err2 != nil {
						mu.Lock()
						c.mismatch++
						mu.Unlock()
						return false
					}
					var a, b any
					da := json.NewDecoder(bytes.NewReader(raw))
					da.UseNumber()
					db := json.NewDecoder(bytes.NewReader(got))
					db.UseNumber()
					if da.Decode(&a) != nil || db.Decode(&b) != nil || !jsonEqual(a, b) {
						mu.Lock()
						c.mismatch++
						c.note("exe-mismatch", f)
						mu.Unlock()
						return false
					}
					mu.Lock()
					c.pass++
					mu.Unlock()
					return true
				}()
				_ = ok
			}
		}()
	}
	for _, f := range files {
		jobs <- f
	}
	close(jobs)
	wg.Wait()
}

func hashStr(s string) uint32 {
	var h uint32 = 2166136261
	for _, c := range s {
		h ^= uint32(c)
		h *= 16777619
	}
	return h
}

func firstWords(s string, n int) string {
	fs := strings.FieldsFunc(s, func(r rune) bool { return r == ' ' || r == ':' || r == '(' || r == ',' })
	if len(fs) > n {
		fs = fs[:n]
	}
	return strings.Join(fs, " ")
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

func (c *counter) note(kind, msg string) {
	if _, ok := c.firstFails[kind]; !ok {
		c.firstFails[kind] = msg
	}
}

type runResult struct {
	ok     bool
	stdout string
	stderr string
}

func run(exe, _ string, args ...string) (runResult, error) {
	cmd := exec.Command(exe, args...)
	var out, errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	rc := 0
	if ee, ok := err.(*exec.ExitError); ok {
		rc = ee.ExitCode()
	} else if err != nil {
		return runResult{false, "", ""}, err
	}
	return runResult{rc == 0, out.String(), errb.String()}, nil
}

// jsonEqual：值语义比较（对象键序不敏感、数组序敏感、数值文本不等时数值比）
func jsonEqual(a, b any) bool {
	switch av := a.(type) {
	case map[string]any:
		bv, ok := b.(map[string]any)
		if !ok || len(av) != len(bv) {
			return false
		}
		for k, v := range av {
			bvv, ok := bv[k]
			if !ok || !jsonEqual(v, bvv) {
				return false
			}
		}
		return true
	case []any:
		bv, ok := b.([]any)
		if !ok || len(av) != len(bv) {
			return false
		}
		for i := range av {
			if !jsonEqual(av[i], bv[i]) {
				return false
			}
		}
		return true
	case json.Number:
		bv, ok := b.(json.Number)
		if !ok {
			return false
		}
		if av.String() == bv.String() {
			return true
		}
		var fa, fb float64
		fmt.Sscan(av.String(), &fa)
		fmt.Sscan(bv.String(), &fb)
		return fa == fb
	default:
		return a == b
	}
}

// untar：git archive 输出解包（仅文件，够用）
func untar(dst string, r io.Reader) error {
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return err
	}
	tr := tar.NewReader(r)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if hdr.Typeflag != tar.TypeReg {
			continue
		}
		p := filepath.Join(dst, hdr.Name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return err
		}
		f, err := os.Create(p)
		if err != nil {
			return err
		}
		if _, err := io.Copy(f, tr); err != nil {
			f.Close()
			return err
		}
		f.Close()
	}
}
