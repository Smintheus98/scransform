import std / [osproc, strutils, strformat, sequtils, parseopt, options]
import guiDialog

type
  TState = enum
    normal, left, inverted, right
#  Reference = enum
#    relative, absolute
  Mode = enum
    get, gui, reset, relative, absolute

  Device = string
  InputDevice = Device
  OutputDevice = Device

  CmdLineParsing = tuple
    mode: Option[Mode]
    tstate: Option[TState]
    odev: Option[OutputDevice]


let
  tMatrix: array[TState, array[9, int]] = [
    [ 1,  0,  0,  0,  1,  0,  0,  0,  1],
    [ 0, -1,  1,  1,  0,  0,  0,  0,  1],
    [-1,  0,  1,  0, -1,  1,  0,  0,  1],
    [ 0,  1,  0, -1,  0,  1,  0,  0,  1],
  ]


proc printUsage() =
  echo """ transform - Screen and pointer rotation tool
Usage:
    transform [OPTIONS]
Options:
    -h, --help              Shows this help menu
    -g, --get               Returns current rotation
    -u, --gui               Opens GUI-dialog
    -d, --reset-default     Resets default configuration
    -r, --relative=ROT      Rotates screen relatively to current rotation
                            with ROT in {normal, left, inverted, right}
    -a, --absolute=ROT      Applys absolute screen rotation
    -m, --monitor           Set specific monitor
                            if not set the main monitor is rotated
"""

proc errorMsg(msg: string) {.inline.} =
  stderr.writeLine(fmt"ERROR: {msg}")

proc errorQuit(msg: string) {.inline.} =
  errorMsg(msg)
  quit QuitFailure


proc getXrandrQuery(): seq[string] =
  execProcess("xrandr", args = ["--query"], options = {poUsePath}).strip.splitLines

proc getXrandrMonitors(): seq[string] =
  result = execProcess("xrandr", args = ["--listmonitors"], options = {poUsePath}).strip.splitLines[1..^1].mapIt(it.split()[^1])
  if result.len == 0:
    errorQuit("No monitors found!")

proc setXrandrRotation(dev: OutputDevice = "eDP1"; tstate: TState): int {.discardable.} =
  execCmd("xrandr --output '$#' --rotate $#" % [dev, $tstate])

proc getXinputList(): seq[string] =
  execProcess("xinput", args = ["list"], options = {poUsePath}).strip.splitLines

proc getXinputListNames(): seq[string] =
  execProcess("xinput", args = ["list", "--name-only"], options = {poUsePath}).strip.splitLines

proc getXinputListPointers(): seq[string] =
  let pointerCount = getXinputList().countIt("pointer" in it)
  return getXinputListNames()[0..<pointerCount]

proc setXinputRotation(dev: InputDevice; tstate: TState): int {.discardable.} =
  execCmd(fmt"xinput set-prop '$#' 'Coordinate Transformation Matrix' $#" % [dev, tMatrix[tstate].join(" ")])

proc getRotState(dev: OutputDevice = "eDP1"): TState =
  let query = getXrandrQuery()
  for line in query:
    if line.startswith(dev):
      let strstate = line.split[4]
      if strstate.startswith("("):
        return normal
      else:
        return parseEnum[TState](strstate)

proc setRotState(odev: OutputDevice = "eDP1"; idevs: seq[InputDevice] = @[]; tstate: TState) =
  setXrandrRotation(odev, tstate)
  for idev in idevs:
    setXinputRotation(idev, tstate)

proc shiftRotState(start, by: TState): TState =
  return ((start.ord + by.ord) mod TState.toSeq.len).TState

proc relToAbsRot(odev: OutputDevice; relRot: TState): TState =
  return shiftRotState(getRotState(odev), relRot)

proc askRotGui(): TState =
  var setting = showGui(getXrandrMonitors())
  let rotstate = getRotState(setting.monitor)
  case setting.action:
    of "Keep":
      return rotstate
    of "Left", "Inverted", "Right":
      var rot = parseEnum[TState](setting.action.toLower)
      if setting.absolute:
        return rot
      else:
        return shiftRotState(rotstate, rot)
    of "Reset":
      return normal
    else: discard


proc trySetMode(res: var CmdLineParsing; mode: Mode) {.inline.} =
  if res.mode.isSome:
    errorQuit("Conflicting modes: '$#' and '$#'" % [$res.mode.get, $mode])
  res.mode = some(mode)


proc trySetTstate(res: var CmdLineParsing; val, optname: string) {.inline.} =
  if val == "":
    errorQuit("Missing Argument for option '$#'" % [optname])
  try:
    res.tstate = some(parseEnum[TState](val))
  except:
    errorQuit("Invalid Argument for option '$#': '$#'" % [optname, val])


proc parseCmdLine(): CmdLineParsing  =
  ## Parsing and formal check (no content check)
  var parser = initOptParser(shortNoVal = {'g', 'd', 'u', 'h'}, longNoVal = @["get", "reset-default", "gui", "help"])

  for kind, key, val in parser.getopt():
    case kind:
      of cmdShortOption, cmdLongOption:
        let optname = (if kind == cmdShortOption: "-" else: "--") & key
        case key:
          of "h", "help":
            printUsage()
            quit QuitSuccess
          of "g", "get":
            result.trySetMode(get)
          of "u", "gui":
            result.trySetMode(gui)
          of "d", "reset-default":
            result.trySetMode(reset)
          of "r", "relative":
            result.trySetMode(relative)
            result.trySetTstate(val, optname)
          of "a", "absolute":
            result.trySetMode(absolute)
            result.trySetTstate(val, optname)
          of "m", "monitor":
            if val == "": errorQuit(fmt"Missing Argument for option '{optname}'")
            result.odev = some(val)
          else:
            errorMsg(fmt"No such option: '{key}'")
            printUsage()
            quit QuitFailure
      of cmdArgument:
        errorMsg(fmt"Invalid argument: '{key}'")
        printUsage()
        quit QuitFailure
      of cmdEnd:
        discard

  if result.mode.isNone:
    result.mode = some(gui)


proc interpretParsedCmdLine(parsing: CmdLineParsing) =
  let
    odevs = getXrandrMonitors()
    idevs = getXinputListPointers()
  var
    mode: Mode
    tstate: TState
    odev: OutputDevice

  if parsing.mode.isSome:
    mode = parsing.mode.get
  if parsing.tstate.isSome:
    tstate = parsing.tstate.get
  if parsing.odev.isSome:
    odev = parsing.odev.get
    if odev notin odevs:
      errorQuit(fmt"No Monitor found with name: '{odev}'")
  else:
    odev = odevs[0]

  case mode:
    of get:
      echo "Rotation:\t$1" % [$getRotState(odev)]
      return
    of gui:
      tstate = askRotGui()
    of reset:
      tstate = normal
    of relative:
      tstate = relToAbsRot(odev, tstate)
    of absolute:
      tstate = tstate

  setRotState(odev, idevs, tstate)


proc main() =
  let parsing = parseCmdLine()
  parsing.interpretParsedCmdLine()

when isMainModule:
  main()
