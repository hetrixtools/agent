import std/[base64, json, os, osproc, parsecfg, random, strformat, strutils, tables, times, uri]

const
  Version = "2.3.8"
  DefaultConfigPath = "/etc/hetrixtools/hetrixtools.cfg"
  DefaultLogPath = "/etc/hetrixtools/hetrixtools_agent.log"

type
  AgentConfig = object
    sid: string
    networkInterfaces: string
    checkServices: string
    checkSoftRaid: int
    checkDriveHealth: int
    runningProcesses: int
    connectionPorts: string
    customVars: string
    securedConnection: int
    collectEveryXSeconds: int
    debug: int
    outgoingPings: string
    outgoingPingsCount: int

  StatSample = object
    cpu: float
    wa: float
    st: float
    us: float
    sy: float
    ram: float
    ramSwap: float
    ramBuff: float
    ramCache: float
    load1: float
    load5: float
    load15: float
    nicRx: Table[string, float]
    nicTx: Table[string, float]

proc cmdOut(command: string): string =
  try:
    result = execProcess(command, options = {poUsePath, poEvalCommand}).strip()
  except CatchableError:
    result = ""

proc parseIntSafe(s: string, d: int = 0): int =
  try:
    result = parseInt(s.strip())
  except ValueError:
    result = d

proc parseFloatSafe(s: string, d: float = 0.0): float =
  try:
    result = parseFloat(s.strip())
  except ValueError:
    result = d

proc nowB64(): string =
  encode(now().format("yyyy-MM-dd HH:mm:ss zzz")).replace("\n", "")

proc parseCfg(path: string): AgentConfig =
  var p: Config
  p = loadConfig(path)
  result.sid = p.getSectionValue("", "SID", "")
  result.networkInterfaces = p.getSectionValue("", "NetworkInterfaces", "")
  result.checkServices = p.getSectionValue("", "CheckServices", "")
  result.checkSoftRaid = parseIntSafe(p.getSectionValue("", "CheckSoftRAID", "0"))
  result.checkDriveHealth = parseIntSafe(p.getSectionValue("", "CheckDriveHealth", "0"))
  result.runningProcesses = parseIntSafe(p.getSectionValue("", "RunningProcesses", "0"))
  result.connectionPorts = p.getSectionValue("", "ConnectionPorts", "")
  result.customVars = p.getSectionValue("", "CustomVars", "custom_variables.json")
  result.securedConnection = parseIntSafe(p.getSectionValue("", "SecuredConnection", "1"), 1)
  result.collectEveryXSeconds = parseIntSafe(p.getSectionValue("", "CollectEveryXSeconds", "3"), 3)
  if result.collectEveryXSeconds < 1:
    result.collectEveryXSeconds = 3
  result.debug = parseIntSafe(p.getSectionValue("", "DEBUG", "0"))
  result.outgoingPings = p.getSectionValue("", "OutgoingPings", "")
  result.outgoingPingsCount = parseIntSafe(p.getSectionValue("", "OutgoingPingsCount", "20"), 20)

proc readLinesSafe(path: string): seq[string] =
  if not fileExists(path):
    return @[]
  result = readFile(path).splitLines()

proc kvFromFile(path: string, sep: string = ":"): Table[string, string] =
  result = initTable[string, string]()
  for ln in readLinesSafe(path):
    if ln.contains(sep):
      let p = ln.split(sep, maxsplit = 1)
      if p.len == 2:
        result[p[0].strip()] = p[1].strip()

proc getMemInfo(): Table[string, int64] =
  result = initTable[string, int64]()
  for ln in readLinesSafe("/proc/meminfo"):
    let parts = ln.splitWhitespace()
    if parts.len >= 2:
      let key = parts[0].replace(":", "")
      result[key] = int64(parseIntSafe(parts[1]))

proc getLoad(): tuple[l1: float, l5: float, l15: float] =
  let parts = readFile("/proc/loadavg").splitWhitespace()
  if parts.len >= 3:
    return (parseFloatSafe(parts[0]), parseFloatSafe(parts[1]), parseFloatSafe(parts[2]))
  (0.0, 0.0, 0.0)

proc readCpuStat(): array[8, int64] =
  let lns = readLinesSafe("/proc/stat")
  for ln in lns:
    if ln.startsWith("cpu "):
      let p = ln.splitWhitespace()
      if p.len >= 8:
        for i in 1..8:
          result[i - 1] = int64(parseIntSafe(p[i]))
      return

proc cpuFromDelta(a, b: array[8, int64]): tuple[cpu, wa, st, us, sy: float] =
  let
    user = (b[0] + b[1]) - (a[0] + a[1])
    system = b[2] - a[2]
    idle = b[3] - a[3]
    iowait = b[4] - a[4]
    steal = b[7] - a[7]
    total = (user + system + idle + iowait + (b[5]-a[5]) + (b[6]-a[6]) + steal).float
  if total <= 0:
    return (0.0, 0.0, 0.0, 0.0, 0.0)
  let
    us = user.float * 100.0 / total
    sy = system.float * 100.0 / total
    wa = iowait.float * 100.0 / total
    st = steal.float * 100.0 / total
  (100.0 - (idle.float * 100.0 / total), wa, st, us, sy)

proc readNetCounters(): Table[string, tuple[rx, tx: int64]] =
  result = initTable[string, tuple[rx, tx: int64]]()
  for ln in readLinesSafe("/proc/net/dev"):
    if not ln.contains(":"):
      continue
    let p = ln.split(":")
    if p.len != 2:
      continue
    let iface = p[0].strip()
    let vals = p[1].splitWhitespace()
    if vals.len >= 10:
      result[iface] = (int64(parseIntSafe(vals[0])), int64(parseIntSafe(vals[8])))

proc splitCsv(s: string): seq[string] =
  for part in s.split(","):
    let v = part.strip()
    if v.len > 0:
      result.add(v)

proc detectNics(cfgNics: string): seq[string] =
  if cfgNics.strip().len > 0:
    return splitCsv(cfgNics)
  let all = readNetCounters()
  for nic in all.keys:
    if nic != "lo":
      result.add(nic)

proc getOsPretty(): string =
  for ln in readLinesSafe("/etc/os-release"):
    if ln.startsWith("PRETTY_NAME="):
      return ln.split("=", maxsplit = 1)[1].strip(chars = {'"', '\''})
  let output = cmdOut("uname -s")
  if output.len > 0: output else: "Linux"

proc getUptimeSeconds(): int64 =
  let up = readFile("/proc/uptime").splitWhitespace()
  if up.len > 0:
    return int64(parseIntSafe(up[0].split(".")[0]))
  0'i64

proc getCpuModel(): string =
  for ln in readLinesSafe("/proc/cpuinfo"):
    if ln.startsWith("model name"):
      return ln.split(":", maxsplit = 1)[1].strip()
  cmdOut("lscpu | awk -F': ' '/Model name/ {print $2; exit}'")

proc getCpuCores(): int =
  var c = 0
  for ln in readLinesSafe("/proc/cpuinfo"):
    if ln.startsWith("processor"):
      inc c
  if c == 0: 1 else: c

proc getCpuThreads(): int =
  let output = cmdOut("lscpu | awk -F': ' '/Thread\\(s\\) per core/ {print $2; exit}'")
  let v = parseIntSafe(output, 1)
  if v < 1: 1 else: v

proc getCpuSockets(): int =
  let output = cmdOut("grep -i 'physical id' /proc/cpuinfo | sort -u | wc -l")
  let v = parseIntSafe(output, 1)
  if v < 1: 1 else: v

proc getCpuSpeed(): int =
  let output = cmdOut("grep -m1 'cpu MHz' /proc/cpuinfo | awk -F': ' '{print $2}'")
  int(parseFloatSafe(output, 0.0))

proc getDiskUsageBase64(): string =
  var entries: seq[string] = @[]
  let output = cmdOut("df -TPB1 2>/dev/null || df -l -TPB1 2>/dev/null")
  for ln in output.splitLines():
    if ln.startsWith("Filesystem") or ln.contains(" tmpfs "):
      continue
    let p = ln.splitWhitespace()
    if p.len >= 7:
      entries.add(fmt"{p[^1]},{p[1]},{p[2]},{p[3]},{p[4]};")
  encode(entries.join(""))

proc getInodesBase64(): string =
  var entries: seq[string] = @[]
  let output = cmdOut("df -Ti 2>/dev/null || df -l -Ti 2>/dev/null")
  for ln in output.splitLines():
    if ln.startsWith("Filesystem") or ln.contains("tmpfs"):
      continue
    let p = ln.splitWhitespace()
    if p.len >= 7:
      entries.add(fmt"{p[^1]},{p[2]},{p[3]},{p[4]};")
  encode(entries.join(""))

proc getIPv4Base64(nics: seq[string]): string =
  var entries: seq[string] = @[]
  for nic in nics:
    let ips = cmdOut(fmt"ip -4 addr show {nic} | awk '/inet / {{print $2}}' | cut -d/ -f1 | paste -sd, -")
    entries.add(fmt"{nic},{ips};")
  encode(entries.join(""))

proc getIPv6Base64(nics: seq[string]): string =
  var entries: seq[string] = @[]
  for nic in nics:
    let ips = cmdOut(fmt"ip -6 addr show {nic} | awk '/scope global/ {{print $2}}' | cut -d/ -f1 | paste -sd, -")
    entries.add(fmt"{nic},{ips};")
  encode(entries.join(""))

proc buildCustomVarsBase64(configPath: string, customVarsPath: string): string =
  if customVarsPath.len == 0:
    return ""
  let baseDir = parentDir(configPath)
  let target = joinPath(baseDir, customVarsPath)
  if fileExists(target):
    return encode(readFile(target))
  ""

proc sleepMs(ms: int) =
  if ms > 0:
    sleep(ms)

proc collectSamples(cfg: AgentConfig, nics: seq[string]): StatSample =
  var
    iterations = max(1, 60 div cfg.collectEveryXSeconds)
    totalCpu = 0.0
    totalWa = 0.0
    totalSt = 0.0
    totalUs = 0.0
    totalSy = 0.0
    totalRam = 0.0
    totalRamSwap = 0.0
    totalBuff = 0.0
    totalCache = 0.0
    totalL1 = 0.0
    totalL5 = 0.0
    totalL15 = 0.0
  result.nicRx = initTable[string, float]()
  result.nicTx = initTable[string, float]()
  for nic in nics:
    result.nicRx[nic] = 0
    result.nicTx[nic] = 0

  for _ in 0..<iterations:
    let cpuA = readCpuStat()
    let netA = readNetCounters()
    sleepMs(cfg.collectEveryXSeconds * 1000)
    let cpuB = readCpuStat()
    let netB = readNetCounters()
    let cpu = cpuFromDelta(cpuA, cpuB)
    totalCpu += cpu.cpu
    totalWa += cpu.wa
    totalSt += cpu.st
    totalUs += cpu.us
    totalSy += cpu.sy
    let mem = getMemInfo()
    let totalMem = max(1'i64, mem.getOrDefault("MemTotal", 1))
    let freeMem = mem.getOrDefault("MemFree", 0)
    let buffMem = mem.getOrDefault("Buffers", 0)
    let cacheMem = mem.getOrDefault("Cached", 0)
    let swapTotal = mem.getOrDefault("SwapTotal", 0)
    let swapFree = mem.getOrDefault("SwapFree", 0)
    let usedPct = ((totalMem - freeMem - buffMem - cacheMem).float * 100.0 / totalMem.float)
    totalRam += max(0.0, min(100.0, usedPct))
    totalBuff += (buffMem.float * 100.0 / totalMem.float)
    totalCache += (cacheMem.float * 100.0 / totalMem.float)
    if swapTotal > 0:
      totalRamSwap += ((swapTotal - swapFree).float * 100.0 / swapTotal.float)
    let l = getLoad()
    totalL1 += l.l1
    totalL5 += l.l5
    totalL15 += l.l15

    for nic in nics:
      if netA.hasKey(nic) and netB.hasKey(nic):
        let rxDelta = (netB[nic].rx - netA[nic].rx).float / cfg.collectEveryXSeconds.float
        let txDelta = (netB[nic].tx - netA[nic].tx).float / cfg.collectEveryXSeconds.float
        result.nicRx[nic] = result.nicRx[nic] + max(0.0, rxDelta)
        result.nicTx[nic] = result.nicTx[nic] + max(0.0, txDelta)

  result.cpu = totalCpu / iterations.float
  result.wa = totalWa / iterations.float
  result.st = totalSt / iterations.float
  result.us = totalUs / iterations.float
  result.sy = totalSy / iterations.float
  result.ram = totalRam / iterations.float
  result.ramSwap = totalRamSwap / iterations.float
  result.ramBuff = totalBuff / iterations.float
  result.ramCache = totalCache / iterations.float
  result.load1 = totalL1 / iterations.float
  result.load5 = totalL5 / iterations.float
  result.load15 = totalL15 / iterations.float
  for nic in nics:
    result.nicRx[nic] = result.nicRx[nic] / iterations.float
    result.nicTx[nic] = result.nicTx[nic] / iterations.float

proc buildNicsBase64(stats: StatSample, nics: seq[string]): string =
  var s = ""
  for nic in nics:
    s.add(fmt"{nic},{stats.nicRx.getOrDefault(nic, 0).int},{stats.nicTx.getOrDefault(nic, 0).int};")
  encode(s)

proc buildPayload(cfg: AgentConfig, configPath: string): JsonNode =
  let
    nics = detectNics(cfg.networkInterfaces)
    stats = collectSamples(cfg, nics)
    osName = encode(getOsPretty())
    kernel = encode(cmdOut("uname -r"))
    hostname = encode(cmdOut("uname -n"))
    user = getEnv("USER", cmdOut("whoami"))
    uptime = $getUptimeSeconds()
    cpuModel = encode(getCpuModel())
    cpuSockets = $getCpuSockets()
    cpuCores = $getCpuCores()
    cpuThreads = $getCpuThreads()
    cpuSpeed = $getCpuSpeed()
    mem = getMemInfo()
    ramSize = $mem.getOrDefault("MemTotal", 0)
    ramSwapSize = $mem.getOrDefault("SwapTotal", 0)
    customVars = buildCustomVarsBase64(configPath, cfg.customVars)

  result = %*{
    "version": Version,
    "SID": cfg.sid,
    "agent": "0",
    "user": user,
    "os": osName,
    "kernel": kernel,
    "hostname": hostname,
    "time": nowB64(),
    "reqreboot": (if fileExists("/var/run/reboot-required"): "1" else: "0"),
    "uptime": uptime,
    "cpumodel": cpuModel,
    "cpusockets": cpuSockets,
    "cpucores": cpuCores,
    "cputhreads": cpuThreads,
    "cpuspeed": cpuSpeed,
    "cpu": $(stats.cpu),
    "wa": $(stats.wa),
    "st": $(stats.st),
    "us": $(stats.us),
    "sy": $(stats.sy),
    "load1": $(stats.load1),
    "load5": $(stats.load5),
    "load15": $(stats.load15),
    "ramsize": ramSize,
    "ram": $(stats.ram),
    "ramswapsize": ramSwapSize,
    "ramswap": $(stats.ramSwap),
    "rambuff": $(stats.ramBuff),
    "ramcache": $(stats.ramCache),
    "disks": getDiskUsageBase64(),
    "inodes": getInodesBase64(),
    "iops": "",
    "raid": "",
    "zp": "",
    "dh": "",
    "nics": buildNicsBase64(stats, nics),
    "ipv4": getIPv4Base64(nics),
    "ipv6": getIPv6Base64(nics),
    "conn": "",
    "temp": "",
    "serv": "",
    "cust": customVars,
    "oping": "",
    "rps1": "",
    "rps2": ""
  }

proc gzipBase64(s: string): string =
  let tmpPath = joinPath(getTempDir(), fmt"hetrixtools_payload_{epochTime().int}_{rand(100000)}.json")
  writeFile(tmpPath, s)
  try:
    result = cmdOut(fmt"gzip -cf {tmpPath.quoteShell} | base64 -w 0")
  finally:
    if fileExists(tmpPath):
      removeFile(tmpPath)

proc writeAndPost(payload: JsonNode, logPath: string, securedConnection: int, noPost: bool) =
  let jsonRaw = $payload
  let encoded = encodeUrl(gzipBase64(jsonRaw))
  writeFile(logPath, "j=" & encoded & "\n")
  if noPost:
    return
  let certOpt = if securedConnection > 0: "" else: "--no-check-certificate "
  discard execCmd(fmt"wget --retry-connrefused --waitretry=1 -t 3 -T 15 -qO- --post-file={logPath} {certOpt}https://sm.hetrixtools.net/v2/ >/dev/null 2>&1")

proc secondsToNextMinute(): int =
  let n = now()
  result = 60 - n.second
  if result <= 0:
    result = 60

proc runAgent(configPath: string, logPath: string, oneShot: bool, noPost: bool) =
  let cfg = parseCfg(configPath)
  if cfg.sid.len == 0:
    stderr.writeLine("ERROR: SID is empty in config.")
    quit(1)
  if oneShot:
    let payload = buildPayload(cfg, configPath)
    writeAndPost(payload, logPath, cfg.securedConnection, noPost)
    return
  while true:
    let payload = buildPayload(cfg, configPath)
    writeAndPost(payload, logPath, cfg.securedConnection, noPost)
    sleep(secondsToNextMinute() * 1000)

when isMainModule:
  var
    configPath = DefaultConfigPath
    logPath = DefaultLogPath
    oneShot = false
    noPost = false
  for arg in commandLineParams():
    if arg == "--once":
      oneShot = true
    elif arg == "--no-post":
      noPost = true
    elif arg.startsWith("--config="):
      configPath = arg.split("=", maxsplit = 1)[1]
    elif arg.startsWith("--log="):
      logPath = arg.split("=", maxsplit = 1)[1]
  runAgent(configPath, logPath, oneShot, noPost)
