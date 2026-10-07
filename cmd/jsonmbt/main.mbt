// jsonmbt CLI（P1 动词面：build / check）
// 契约（D-10/D-8）：rc 0 成功 / 1 输入错 / 4 用法·IO 错（2=漂移差异、3=保留，P1 未占用）；
// 诊断走 stderr（机器可读前缀 jsonmbt: error [Jxxxx] path:line:col …）；
// build 产物走文件（默认同名 .json）或 stdout（stdin `-` 时）；原子写 = 临时文件 + rename；
// 校验先行失败零产物（check = build 的 dry-run——同一条校验路径）

///|
fn write_stderr(s : String) -> Unit {
  // 长度必须是 UTF-8 字节数（s.length() 是码元数——多字节字符按码元数
  // 写入会截尾，issue #1：em-dash 每个多丢 2 字节）
  let bytes = @unicode.to_utf8_bytes(s)
  jsonmbt_write_stderr(bytes, bytes.length())
}

///|
/// J 码诊断单源出口（审 P3：CLI 15 处手写 [Jxxxx] 前缀 → 统一走 Diag 构造，
/// 码值与渲染只此一家）
fn jdiag_exit(code : @src.JCode, msg : String, help? : String? = None) -> Int {
  let d = @src.Diag(code~, loc=dummy_loc(), message=msg, help~, path="")
  write_stderr(d.render())
  @src.JCode::exit_code(code)
}

///|
fn usage() -> Int {
  write_stderr(
    "jsonmbt — typed JSON source files for MoonBit (.json.mbt)\n" +
    "usage:\n" +
    "  jsonmbt build <file.json.mbt...|-> [-o <out.json>]\n" +
    "  jsonmbt check <file.json.mbt...|->\n" +
    "  jsonmbt import <file.json|-> [-o <out.json.mbt>] [--check]\n" +
    "degrade: .json.mbt -> .json (deterministic, compact); `-` reads stdin\n" +
    "ingest: .json/.jsonc -> .json.mbt (shape inference); --check = idempotence gate\n" +
    "rc: 0 ok / 1 input error / 2 drift detected (--check) / 4 usage/IO",
  )
  4
}

///|
/// hint 渲染（rc-0 提示走 stderr；前缀 jsonmbt: hint——机器可读同 D-10 纪律）
fn print_hint(e : @src.Diag) -> Unit {
  write_stderr(
    e.render().replace(old="jsonmbt: error [", new="jsonmbt: hint ["),
  )
}

///|
/// 行尾归一（CRLF→LF）后比对（纪律 11：幂等闸的比对口径）
fn normalize_eol(s : String) -> String {
  s.replace(old="\r\n", new="\n")
}

///|
/// 输出文件名 → stem：.json.mbt 整后缀优先剥（si.json.mbt → si，
/// 审 P2-1：只去最后一段会产出非法 `pub let si.json`）；其余形态退化到末段
fn json_stem_of(path : String) -> String? {
  let base = basename(path)
  if base.has_suffix(".json.mbt") && base.length() > ".json.mbt".length() {
    return Some(base[:base.length() - ".json.mbt".length()].to_owned())
  }
  let dot = base.rev_find(".")
  match dot {
    Some(i) => if i > 0 { Some(base[:i].to_owned()) } else { None }
    None => Some(base)
  }
}

///|
fn run_import(path : String, out_opt : String?, check : Bool) -> Int {
  let src = read_input(path) catch {
    e =>
      if e is @src.Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "cannot read '\{path}'")
      }
  }
  // stem：文件名去扩展；stdin 必须配 -o（从 -o 取 stem——D-7 命名同源）
  let display = if path == "-" { "<stdin>" } else { path }
  let stem = if path == "-" {
    match out_opt {
      Some(o) =>
        match json_stem_of(o) {
          Some(s) => s
          None =>
            return jdiag_exit(
              @src.JUsage,
              "-o needs a file name to derive the stem from",
            )
        }
      None =>
        return jdiag_exit(
          @src.JUsage,
          "importing stdin requires -o <out.json.mbt>",
        )
    }
  } else {
    match json_stem_of(path) {
      Some(s) => s
      None => return jdiag_exit(@src.JUsage, "'\{path}' has no usable stem")
    }
  }
  let outcome = @src.import_source(src, path=display, stem~) catch {
    e =>
      if e is @src.Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "internal: non-Diag error")
      }
  }
  for h in outcome.hints {
    print_hint(h)
  }
  let target = match out_opt {
    Some(o) => o
    None => path[:path.length() - ext_len(path)].to_owned() + ".json.mbt"
  }
  if check {
    // 幂等闸（纪律 11）：重算产物与磁盘比对（行尾归一）；漂移 rc 2（D-10）
    let existing = Some(@fs.read_file_to_string(target)) catch { _ => None }
    let up_to_date = match existing {
      Some(disk) => normalize_eol(disk) == normalize_eol(outcome.content)
      None => false
    }
    if up_to_date {
      return 0
    }
    return jdiag_exit(
      @src.JDrift,
      "'\{target}' is not up to date with '\{display}' (import --check)",
      help=Some("re-run: jsonmbt import \{display}"),
    )
  }
  if path == "-" {
    match out_opt {
      Some(_) =>
        // stdin + -o：落盘（usage 承诺；审 P2-1——原实现无条件 println 返回）
        atomic_write(target, outcome.content) catch {
          e =>
            if e is @src.Diag(..) {
              return print_diag_exit(e)
            } else {
              return 4
            }
        }
      None => println(outcome.content)
    }
    return 0
  }
  atomic_write(target, outcome.content) catch {
    e => if e is @src.Diag(..) { return print_diag_exit(e) } else { return 4 }
  }
  0
}

///|
fn ext_len(path : String) -> Int {
  let base = basename(path)
  let dot = base.rev_find(".")
  match dot {
    Some(i) => base.length() - i
    None => 0
  }
}

///|
fn dummy_loc() -> @basic.Location {
  {
    start: { fname: "", lnum: 1, bol: 0, cnum: 0, },
    end: { fname: "", lnum: 1, bol: 0, cnum: 0, },
  }
}

///|
/// J0002：IO 错（无位置语义）
fn io_diag(msg : String) -> @src.Diag {
  @src.Diag(code=@src.JIO, loc=dummy_loc(), message=msg, help=None, path="")
}

///|
fn print_diag_exit(e : @src.Diag) -> Int {
  write_stderr(e.render())
  @src.JCode::exit_code(e.code())
}

///|
/// 末段文件名（跨 / 与 \）
fn basename(path : String) -> String {
  let a = path.rev_find("/")
  let b = path.rev_find("\\")
  let cut = match (a, b) {
    (Some(x), Some(y)) => if x > y { x } else { y }
    (Some(x), None) => x
    (None, Some(y)) => y
    (None, None) => return path
  }
  path[cut + 1:].to_owned()
}

///|
/// config.json.mbt → config；非 .json.mbt 后缀 → None
fn stem_of(path : String) -> String? {
  let base = basename(path)
  if base.has_suffix(".json.mbt") && base.length() > ".json.mbt".length() {
    Some(base[:base.length() - ".json.mbt".length()].to_owned())
  } else {
    None
  }
}

///|
fn read_input(path : String) -> String raise @src.Diag {
  if path == "-" {
    @unicode.to_utf8_string(jsonmbt_read_stdin())
  } else {
    @fs.read_file_to_string(path) catch {
      _ => raise io_diag("cannot read '\{path}'")
    }
  }
}

///|
/// 原子写（D-8 ③）：同目录临时文件 + rename；失败清理临时文件
fn atomic_write(target : String, content : String) -> Unit raise @src.Diag {
  let tmp = target + ".jsonmbt-tmp"
  @fs.write_string_to_file(tmp, content) catch {
    _ => raise io_diag("cannot write '\{tmp}'")
  }
  let from_b = @unicode.to_utf8_bytes(tmp)
  let to_b = @unicode.to_utf8_bytes(target)
  if jsonmbt_rename(from_b, from_b.length(), to_b, to_b.length()) != 0 {
    @fs.remove_file(tmp) catch {
      _ => ()
    }
    raise io_diag("cannot finalize '\{target}' (rename failed)")
  }
}

///|
fn main {
  @sys.exit(main_rc())
}

///|
fn main_rc() -> Int {
  let args = @env.args()
  if args.length() < 3 {
    return usage()
  }
  let verb = args[1]
  if verb != "build" && verb != "check" && verb != "import" {
    return jdiag_exit(@src.JUsage, "unknown command '\{verb}'")
  }
  let paths : Array[String] = []
  let mut out_opt : String? = None
  let mut do_check = false
  let mut do_pretty = false
  let mut i = 2
  while i < args.length() {
    let a = args[i]
    if a == "-o" || a == "--output" {
      if i + 1 >= args.length() {
        return jdiag_exit(@src.JUsage, "-o requires an argument")
      }
      out_opt = Some(args[i + 1])
      i = i + 2
    } else if a == "--check" {
      do_check = true
      i = i + 1
    } else if a == "--pretty" {
      do_pretty = true
      i = i + 1
    } else if a == "-h" || a == "--help" {
      return usage()
    } else {
      paths.push(a)
      i = i + 1
    }
  }
  if paths.length() == 0 {
    return usage()
  }
  // stdin `-` 只允许单输入；build/check 的文件路径必须 .json.mbt 后缀（防误伤）
  for p in paths {
    if p == "-" {
      if paths.length() > 1 {
        return jdiag_exit(@src.JUsage, "'-' (stdin) must be the only input")
      }
    } else if verb != "import" && stem_of(p) is None {
      return jdiag_exit(
        @src.JUsage,
        "'\{p}' is not a .json.mbt file (use `-` for stdin)",
      )
    }
  }
  if verb == "import" {
    if paths.length() != 1 {
      return usage()
    }
    return run_import(paths[0], out_opt, do_check)
  }
  if paths.length() > 1 && out_opt is Some(_) {
    return jdiag_exit(@src.JUsage, "-o accepts a single input")
  }
  let mut rc = 0
  for p in paths {
    let r = run_one(verb, p, out_opt, do_pretty)
    if r != 0 {
      rc = r
    }
  }
  rc
}

///|
fn run_one(
  verb : String,
  path : String,
  out_opt : String?,
  pretty : Bool,
) -> Int {
  let src = read_input(path) catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "cannot read '\{path}'")
      }
  }
  let expected_name = if path == "-" { None } else { stem_of(path) }
  let display = if path == "-" { "<stdin>" } else { path }
  // check = build 的 dry-run（同一条校验路径——D-8）
  if verb == "check" {
    @src.check_source(src, path=display, expected_name?) catch {
      e =>
        if e is Diag(..) {
          return print_diag_exit(e)
        } else {
          return jdiag_exit(@src.JIO, "internal: non-Diag error")
        }
    }
    return 0
  }
  // build：校验先行，失败零产物（D-8 ①）；--pretty 与 Go encoder 逐字节对齐
  let product = @src.build_source(src, path=display, expected_name?, pretty=pretty) catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "internal: non-Diag error")
      }
  }
  // 产物去向：stdin 默认 stdout（-o 可改道文件）；文件默认同名 .json
  if path == "-" {
    match out_opt {
      Some(o) =>
        atomic_write(o, product) catch {
          e => if e is Diag(..) { return print_diag_exit(e) } else { return 4 }
        }
      None => println(product)
    }
    return 0
  }
  let target = match out_opt {
    Some(o) => o
    None => path[:path.length() - ".json.mbt".length()].to_owned() + ".json"
  }
  atomic_write(target, product) catch {
    e => if e is Diag(..) { return print_diag_exit(e) } else { return 4 }
  }
  0
}
