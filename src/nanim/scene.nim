
import
  nanovg,
  glfw,
  glm,
  opengl,
  os,
  times,
  algorithm,
  sequtils


import
  entities/entity,

  animation/tween,
  animation/easings


proc createNVGContext(): Context =
  let flags = {nifStencilStrokes, nifDebug}
  return nvgCreateContext(flags)


proc loadFonts(context: Context) =
  let fontFolderPath = os.joinPath(os.getAppDir(), "fonts")

  echo "Loading fonts from: " & fontFolderPath

  let fontNormal = context.createFont("montserrat", os.joinPath(fontFolderPath, "Montserrat-Regular.ttf"))
  doAssert not (fontNormal == NoFont)

  let fontThin = context.createFont("montserrat-thin", os.joinPath(fontFolderPath, "Montserrat-Thin.ttf"))
  doAssert not (fontThin == NoFont)

  let fontLight = context.createFont("montserrat-light", os.joinPath(fontFolderPath, "Montserrat-Light.ttf"))
  doAssert not (fontLight == NoFont)

  let fontBold = context.createFont("montserrat-bold", os.joinPath(fontFolderPath, "Montserrat-Bold.ttf"))
  doAssert not (fontBold == NoFont)


proc createWindow(resizable: bool = true, width: int = 900, height: int = 500): Window =
  var config = DefaultOpenglWindowConfig
  config.size = (w: width, h: height)
  config.title = "Nanim"
  config.resizable = resizable
  config.nMultiSamples = 8
  config.debugContext = true
  config.bits = (r: 8, g: 8, b: 8, a: 8, stencil: 8, depth: 16)
  config.version = glv30

  let window = newWindow(config)
  if window == nil: quit(-1)

  # Enables vsync
  swapInterval(1)

  return window


type
  Scene* = ref object of RootObj
    window: Window
    context: Context

    width: int
    height: int

    time: float
    lastUpdateTime: float
    deltaTime: float

    frameBufferWidth: int32
    frameBufferHeight: int32

    tweens: seq[Tween]

    currentTweens: seq[Tween]
    oldTweens: seq[Tween]
    futureTweens: seq[Tween]

    entities: seq[Entity]
    projectionMatrix*: Mat4x4[float]

    pixelRatio: float

    done: bool


proc scale*(scene: Scene, d: float = 0): Tween =
  var interpolators: seq[proc(t: float)]

  let
    startValue = scene.projectionMatrix.deepCopy()
    endValue = startValue.scale(vec3(d,d,d))

  let interpolator = proc(t: float) =
    scene.projectionMatrix = interpolate(startValue, endValue, t)

  interpolators.add(interpolator)

  scene.projectionMatrix = endValue

  result = newTween(interpolators,
                    defaultEasing,
                    defaultDuration)


proc rotate*(scene: Scene, angle: float = 0): Tween =
  var interpolators: seq[proc(t: float)]

  let
    startValue = scene.projectionMatrix.deepCopy()
    endValue = startValue.rotateZ(angle)

  let interpolator = proc(t: float) =
    scene.projectionMatrix = interpolate(startValue, endValue, t)

  interpolators.add(interpolator)

  scene.projectionMatrix = endValue

  result = newTween(interpolators,
                    defaultEasing,
                    defaultDuration)


proc move*(scene: Scene, dx: float = 0, dy: float = 0, dz: float = 0): Tween =
  var interpolators: seq[proc(t: float)]

  let
    startValue = scene.projectionMatrix.deepCopy()
    endValue = startValue.translate(vec3(dx, dy, dz))

  let interpolator = proc(t: float) =
    scene.projectionMatrix = interpolate(startValue, endValue, t)

  interpolators.add(interpolator)

  scene.projectionMatrix = endValue

  result = newTween(interpolators,
                    defaultEasing,
                    defaultDuration)


proc newScene*(): Scene =
  new(result)
  result.time = cpuTime()
  result.lastUpdateTime = -100.0
  result.tweens = @[]
  result.projectionMatrix = mat4x4[float](vec4[float](1,0,0,0),
                                          vec4[float](0,1,0,0),
                                          vec4[float](0,0,1,0),
                                          vec4[float](0,0,0,1))
  result.done = false


proc add*(scene: Scene, entities: varargs[Entity]) =
  scene.entities.add(@entities)


proc animate*(scene: Scene, tweens: varargs[Tween]) =
  var previousEndtime: float

  try:
    let previousTween = scene.tweens[high(scene.tweens)]
    previousEndTime = previousTween.startTime + previousTween.duration
  except IndexDefect:
    previousEndTime = 0.0


  for tween in @tweens:
    tween.startTime = previousEndTime
    scene.tweens.add(tween)


proc play*(scene: Scene, tweens: varargs[Tween]) =
    scene.animate(tweens)


proc wait*(scene: Scene, duration: float = defaultDuration) =
  var interpolators: seq[proc(t: float)]

  interpolators.add(proc(t: float) = discard)

  scene.animate(newTween(interpolators,
                         linear,
                         duration))


proc scaleToUnit(scene: Scene, fraction: float = 1000f) =
  let n = min(scene.width, scene.height).float
  let d = max(scene.width, scene.height).float

  let compensation = (d - n)/2f

  let unit = n / fraction

  if scene.width > scene.height:
    scene.context.translate(compensation, 0f)
  else:
    scene.context.translate(0f, compensation)

  scene.context.scale(unit, unit)


proc clearWithColor(color: Color = rgb(0, 0, 0)) =
  glClearColor(color.r, color.g, color.b, color.a)
  glClear(GL_COLOR_BUFFER_BIT or
          GL_DEPTH_BUFFER_BIT or
          GL_STENCIL_BUFFER_BIT)


func project(point: Vec3[float], projection: Mat4x4[float]): Vec3[float] =
  let v4 = vec4(point.x, point.y, point.z, 1.0)
  let res = projection * v4
  result = vec3(res.x, res.y, res.z)


proc draw*(context: Context, entity: Entity) =
  context.save()

  context.translate(entity.position.x, entity.position.y)
  context.scale(entity.scaling.x, entity.scaling.y)
  context.rotate(entity.rotation)

  entity.draw(context)

  context.restore()


proc draw*(scene: Scene) =
  let context = scene.context

  # discard context.currentTransform()

  glViewport(0, 0, scene.frameBufferWidth, scene.frameBufferHeight)
  context.beginFrame(scene.width.cfloat, scene.height.cfloat, scene.pixelRatio)

  scene.scaleToUnit()

  clearWithColor(rgb(255, 255, 255))

  for entity in scene.entities:
    var intermediate = entity.deepCopy()

    # Apply the scene's projection matrix to every point of every entity
    intermediate.points = sequtils.map(intermediate.points,
                                       proc(point: Vec3[float]): Vec3[float] =
                                         point.project(scene.projectionMatrix))

    context.draw(intermediate)

  context.endFrame()


proc tick(scene: Scene) =
  var (windowWidth, windowHeight) = scene.window.size

  scene.width = windowWidth
  scene.height = windowHeight

  var (frameBufferWidth, frameBufferHeight) = scene.window.framebufferSize

  scene.frameBufferHeight = frameBufferHeight
  scene.frameBufferWidth = frameBufferWidth
  scene.pixelRatio = 1

  # By first evaluating all future tweens in reverse order, then old tweens and
  # finally the current ones, we assure that all tween's have been reset and/or
  # completed correctly.
  scene.oldTweens = @[]
  scene.futureTweens = @[]
  scene.currentTweens = @[]

  for tween in scene.tweens:
    if scene.time  > tween.startTime + tween.duration:
      scene.oldTweens.add(tween)
    elif scene.time  < tween.startTime:
      scene.futureTweens.add(tween)
    else:
      scene.currentTweens.add(tween)

    for tween in scene.oldTweens & scene.futureTweens.reversed():
      tween.evaluate(scene.time)

  for tween in scene.currentTweens:
    tween.evaluate(scene.time)

  scene.draw()

  swapBuffers(scene.window)

  scene.lastUpdateTime = cpuTime() * 1000.0

  if len(scene.currentTweens) == 0 and len(scene.futureTweens) == 0:
    scene.done = true


proc update*(scene: Scene) =
  let time = cpuTime() * 1000
  if time - scene.lastUpdateTime >= 1000.0/120.0:
    scene.time = time
    scene.deltaTime = time - scene.lastUpdateTime
    scene.tick()


proc setupCallbacks(scene: Scene) =
  scene.window.framebufferSizeCb = proc(w: Window, s: tuple[w, h: int32]) =
    scene.tick()

  scene.window.windowRefreshCb = proc(w: Window) =
    scene.tick()
    w.swapBuffers()


proc setupRendering(scene: var Scene, resizable: bool = true, width: int = 1920, height: int = 1080) =
  initialize()
  scene.window = createWindow(resizable, width, height)
  if resizable: scene.setupCallbacks()

  doAssert glInit()

  glEnable(GL_MULTISAMPLE)

  makeContextCurrent(scene.window)

  nvgInit(getProcAddress)
  scene.context = createNVGContext()

  scene.context.loadFonts()


proc runLiveRenderingLoop(scene: Scene) =
  # TODO: Make scene.update loop be on a separate thread. That would allow rendering even while user is dragging window...
  while not scene.window.shouldClose:
    scene.update()
    pollEvents()


proc offset(some: pointer; b: int): pointer {.inline.} =
  result = cast[pointer](cast[int](some) + b)


import osproc, streams


proc renderVideo(scene: Scene) =

  let
    width = 1920.cint
    height = 1080.cint
    rgbaSize = 4
    bufferSize = width * height * rgbaSize
    goalFps = 60.0
    goalDeltaTime = 1000.0/goalFps

  scene.time = 0.0
  scene.deltaTime = goalDeltaTime

  var ffmpegProcess = startProcess("ffmpeg", "", @[
    "-y",
    "-f", "rawvideo",
    "-s", $width & "x" & $height,
    "-pix_fmt", "rgba",
    "-r", "60",
    "-i", "-",  # Sets input to pipe
    "-vf", "vflip,format=yuv420p",
    "-an",  # Don't expect audio,
    # "-loglevel", "panic",  # Only log to console if something crashes
    "-c:v", "libx264",  # H.264 encoding
    "-preset", "ultrafast",  # Should probably stay at fast/medium later
    "-crf", "18",  # Ranges 0-51 indicates lossless compression to worst compression. Sane options are 0-30
    "-tune", "animation",  # Tunes the encoder for animation and 'cartoons'
    "-pix_fmt", "yuv420p",
    "out.mp4"
  ], options = {poUsePath, poStdErrToStdOut, poEchoCmd})

  var ffmpegInputStream = ffmpegProcess.inputStream()

  while not scene.window.shouldClose and not scene.done:
    scene.tick()
    scene.time = scene.time + goalDeltaTime

    var data = alloc(bufferSize)
    defer: dealloc(data)

    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, data)

    ffmpegInputStream.writeData(data, bufferSize)
    ffmpegInputStream.flush()

    pollEvents()

  close(ffmpegProcess)
  discard waitForExit(ffmpegProcess)



proc render*(userScene: Scene, createVideo: bool = false, width: int = 1920, height: int = 1080) =
  var scene = userScene.deepCopy()

  scene.setupRendering(createVideo, width, height)

  if createVideo:
    scene.renderVideo()
  else:
    scene.runLiveRenderingLoop()

  nvgDeleteContext(scene.context)
  terminate()
