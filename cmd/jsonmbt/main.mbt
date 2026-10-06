// jsonmbt CLI（P1 动词面：build / check）
// 契约（D-10/D-8）：rc 0 成功 / 1 输入错 / 4 用法·IO 错（2=漂移差异、3=保留，P1 未占用）；
// 诊断走 stderr（机器可读前缀 jsonmbt: error [Jxxxx] path:line:col …）；
// build 产物走文件（默认同名 .json）或 stdout（stdin `-` 时）；原子写 = 临时文件 + rename；
// 校验先行失败零产物（check = build 的 dry-run——同一条校验路径）

fn write_stderr(s : String) -> Unit {
  jsonmbt_write_stderr(@unicode.to_utf8_bytes(s), s.length())
}

///|
fn usage() -> Int {
  write_stderr(
    "jsonmbt — typed JSON source files for MoonBit (.json.mbt)\n" +
    "usage:\n" +
    "  jsonmbt build <file.json.mbt...|-> [-o <out.json>]\n" +
    "  jsonmbt check <file.json.mbt...|->\n" +
    "degrade: .json.mbt -> .json (deterministic, compact); `-` reads stdin\n" +
    "build from stdin writes the product to stdout; rc: 0 ok / 1 input error / 4 usage/IO",
  )
  4
}

///|
fn dummy_loc() -> @basic.Location {
  {
    start: { fname: "", lnum: 1, bol: 0, cnum: 0 },
    end: { fname: "", lnum: 1, bol: 0, cnum: 0 },
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
    try {
      @fs.read_file_to_string(path)
    } catch {
      _ => raise io_diag("cannot read '\{path}'")
    }
  }
}

///|
/// 原子写（D-8 ③）：同目录临时文件 + rename；失败清理临时文件
fn atomic_write(target : String, content : String) -> Unit raise @src.Diag {
  let tmp = target + ".jsonmbt-tmp"
  try {
    @fs.write_string_to_file(tmp, content)
  } catch {
    _ => raise io_diag("cannot write '\{tmp}'")
  }
  let from_b = @unicode.to_utf8_bytes(tmp)
  let to_b = @unicode.to_utf8_bytes(target)
  if jsonmbt_rename(from_b, from_b.length(), to_b, to_b.length()) != 0 {
    try {
      @fs.remove_file(tmp)
    } catch {
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
  if verb != "build" && verb != "check" {
    write_stderr("jsonmbt: error [J0001] unknown command '\{verb}'")
    return 4
  }
  let paths : Array[String] = []
  let mut out_opt : String? = None
  let mut i = 2
  while i < args.length() {
    let a = args[i]
    if a == "-o" || a == "--output" {
      if i + 1 >= args.length() {
        write_stderr("jsonmbt: error [J0001] -o requires an argument")
        return 4
      }
      out_opt = Some(args[i + 1])
      i = i + 2
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
  // stdin `-` 只允许单输入；文件路径必须 .json.mbt 后缀（防误伤源文件）
  for p in paths {
    if p == "-" {
      if paths.length() > 1 {
        write_stderr("jsonmbt: error [J0001] '-' (stdin) must be the only input")
        return 4
      }
    } else if stem_of(p) is None {
      write_stderr(
        "jsonmbt: error [J0001] '\{p}' is not a .json.mbt file (use `-` for stdin)",
      )
      return 4
    }
  }
  if paths.length() > 1 && out_opt is Some(_) {
    write_stderr("jsonmbt: error [J0001] -o accepts a single input")
    return 4
  }
  let mut rc = 0
  for p in paths {
    let r = run_one(verb, p, out_opt)
    if r != 0 {
      rc = r
    }
  }
  rc
}

///|
fn run_one(verb : String, path : String, out_opt : String?) -> Int {
  let src = try {
    read_input(path)
  } catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        write_stderr("jsonmbt: error [J0002] cannot read '\{path}'")
        return 4
      }
  }
  let expected_name = if path == "-" { None } else { stem_of(path) }
  let display = if path == "-" { "<stdin>" } else { path }
  // check = build 的 dry-run（同一条校验路径——D-8）
  if verb == "check" {
    try {
      @src.check_source(src, path=display, expected_name?)
    } catch {
      e =>
        if e is Diag(..) {
          return print_diag_exit(e)
        } else {
          write_stderr("jsonmbt: error [J0002] internal: non-Diag error")
          return 4
        }
    }
    return 0
  }
  // build：校验先行，失败零产物（D-8 ①）
  let product = try {
    @src.build_source(src, path=display, expected_name?)
  } catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        write_stderr("jsonmbt: error [J0002] internal: non-Diag error")
        return 4
      }
  }
  // 产物去向：stdin 默认 stdout（-o 可改道文件）；文件默认同名 .json
  if path == "-" {
    match out_opt {
      Some(o) =>
        try {
          atomic_write(o, product)
        } catch {
          e =>
            if e is Diag(..) {
              return print_diag_exit(e)
            } else {
              return 4
            }
        }
      None => {
        println(product)
      }
    }
    return 0
  }
  let target = match out_opt {
    Some(o) => o
    None =>
      path[:path.length() - ".json.mbt".length()].to_owned() + ".json"
  }
  try {
    atomic_write(target, product)
  } catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        return 4
      }
  }
  0
}
