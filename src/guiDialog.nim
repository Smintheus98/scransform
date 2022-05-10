import sequtils
import nigui

type Setting* = tuple
  action: string
  monitor: string
  absolute: bool


proc showGui*(monitors: seq[string]; wname: string = "Scransform"): Setting =
  app.init()
  var setting: Setting
  if monitors.len() <= 0:
    return
  
  var window = newWindow(wname)
  window.width = 500.scaleToDpi
  window.height = 500.scaleToDpi

  var subContainer1 = newLayoutContainer(Layout_Horizontal)
  subContainer1.widthMode = WidthMode_Expand
  subContainer1.padding = 10
  subContainer1.frame = newFrame()
  subContainer1.spacing = 50
  let comboBoxLabels = @[monitors, @["Relative", "Absolute"]]
  var comboBoxes = comboBoxLabels.mapIt(newComboBox(it))
  for box in comboBoxes:
    box.width = 150
    box.fontSize = 18.0
    subContainer1.add(box)

  var subContainer2 = newLayoutContainer(Layout_Vertical)
  subContainer2.widthMode = WidthMode_Expand
  subContainer2.padding = 20
  subContainer2.frame = newFrame()
  subContainer2.xAlign = XAlign_Center
  subContainer2.yAlign = YAlign_Center
  let buttonLabels = @["Reapply", "Left", "Inverted", "Right", "Reset"]
  var buttons = buttonLabels.mapIt(newButton(it))
  let onClickProcs = buttonLabels.mapIt(
    proc(event: ClickEvent) =
      setting.action = it
      setting.monitor = comboBoxes[0].value
      echo comboBoxes[1].value
      setting.absolute = comboBoxes[1].value == comboBoxLabels[1][1]
      app.quit
  )
  for i, button in buttons:
    button.widthMode = WidthMode_Expand
    button.height = 60
    button.fontSize = 18.0
    button.onClick = onClickProcs[i]
    subContainer2.add(button)


  var mainContainer = newLayoutContainer(Layout_Vertical)
  mainContainer.xAlign = XAlign_Center
  mainContainer.padding = 5
  mainContainer.add(subContainer1)
  mainContainer.add(subContainer2)

  window.add(mainContainer)

  window.show()
  app.run()

  return setting

when isMainModule:
  var s = showGui(@["m1", "m2"])

  echo s
