probe/ 样本与期望产物（层 2 黑盒驱动输入面；黄金值 = build 实测，人工核对）
- server.json.mbt → server.json：基础 struct + Option None
- vitals.json.mbt → vitals.json：全类型（Int64 边值/指数/裸 object/Map/转义）
- reserved_keys.json.mbt → reserved_keys.json：保留字字段名（where）→ where_ 改名
  + field-alias 注记（#13）——build 按注记还原 JSON 键
- 黄金值由 jsonmbt build 生成后逐字节锚定；改一处连跑全部（AGENTS 三层锚纪律）
