//
//  CreditsScene.swift
//  Asteroids
//
//  Copyright © 2020 Daniel Long and David Long
//
//  License: MIT
//
//  See LICENSE.md in the top-level directory for full terms and discussion.
//

import SpriteKit
import SafariServices
import os.log

/// Game credits and acknowledgements
class CreditsScene: BasicScene, SFSafariViewControllerDelegate {
  /// This is `true` when displaying a hyperlink via Safari
  var showingLink = false
  /// The mysterious developers, who knows where they might hide?
  var developers: SKSpriteNode!

  // MARK: - Initialization

  /// Build the stuff in the scene
  func initCredits() {
    let attributes = AttrStyles(fontName: AppAppearance.font, fontSize: 40)
    let credits = SKNode()
    credits.name = "credits"
    credits.setZ(.info)
    addChild(credits)
    // Title
    let title = SKLabelNode(fontNamed: attributes.fontName)
    title.fontSize = 100
    title.fontColor = AppAppearance.highlightTextColor
    title.text = "Credits"
    title.verticalAlignmentMode = .center
    title.position = CGPoint(x: fullFrame.midX, y: fullFrame.maxY - title.fontSize)
    credits.addChild(title)
    // Buttons at the bottom
    let buttonSize = CGSize(width: 150, height: 100)
    let buttonSpacing = CGFloat(20)
    // New game
    let playButton = Button(imageNamed: "playbutton", imageColor: AppAppearance.playButtonColor, size: buttonSize)
    playButton.action = { [unowned self] in self.startGame() }
    // Main menu
    let menuButton = Button(imageNamed: "homebutton", imageColor: AppAppearance.buttonColor, size: buttonSize)
    menuButton.action = { [unowned self] in self.mainMenu() }
    // Settings screen
    let settingsButton = Button(imageNamed: "settingsbutton", imageColor: AppAppearance.buttonColor, size: buttonSize)
    settingsButton.action = { [unowned self] in self.showSettings() }
    let bottomHstack = horizontalStack(nodes: [menuButton, playButton, settingsButton], minSpacing: buttonSpacing)
    bottomHstack.position = CGPoint(x: bottomHstack.position.x,
                                    y: fullFrame.minY + buttonSize.height + buttonSpacing - bottomHstack.position.y)
    credits.addChild(bottomHstack)
    // The actual credits in the center
    let creditsLabels = SKNode()
    creditsLabels.name = "creditsLabels"
    // There are several sections, each with a line or two of text followed by a link
    let creditsText = [
      ("Designed & Programmed by\n@Daniel Long@ and @David Long@",
       "rockrats.davidlong.org"),
      ("Game art & sounds by @Kenney@",
       "www.kenney.nl"),
      ("Thanks to @Paul Hudson@ for\niOS development tutorials",
       "www.hackingwithswift.com")
    ]
    var nextLabelY = CGFloat(0)
    var creditsFrames = [CGRect]()
    for (text, link) in creditsText {
      let creditsLabel = SKLabelNode(attributedText: makeAttributed(text: text, until: text.endIndex, attributes: attributes))
      creditsLabel.name = "creditsLabel"
      creditsLabel.numberOfLines = 0
      creditsLabel.lineBreakMode = .byWordWrapping
      creditsLabel.preferredMaxLayoutWidth = 900
      creditsLabel.horizontalAlignmentMode = .left
      creditsLabel.verticalAlignmentMode = .top
      creditsLabel.position = CGPoint(x: 0, y: nextLabelY)
      creditsLabels.addChild(creditsLabel)
      creditsFrames.append(creditsLabel.frame)
      nextLabelY -= creditsLabel.frame.height + 0.25 * attributes.fontSize
      // Putting links in a button doesn't match the rest of the credits, but I want
      // to indicate that they're activatable in some way.  I settled on using the
      // same green as the button borders for the link text.
      let linkLabel = SKLabelNode(text: link)
      linkLabel.fontName = attributes.fontName
      linkLabel.fontSize = attributes.fontSize
      linkLabel.fontColor = AppAppearance.borderColor
      linkLabel.horizontalAlignmentMode = .left
      linkLabel.verticalAlignmentMode = .top
      linkLabel.position = CGPoint(x: 0, y: nextLabelY)
      creditsLabels.addChild(Touchable(linkLabel) { [unowned self] in self.showLink(link) })
      nextLabelY -= linkLabel.frame.height + 0.75 * attributes.fontSize
    }
    if let gc = Globals.gcInterface, gc.enabled, !achievementIsCompleted(.hideAndSeek) {
      // Add a period after the first credits label
      developers = SKSpriteNode(texture: Globals.textureCache.findTexture(imageNamed: "developers"),
                                size: CGSize(width: 5, height: 5))
      // Blend in
      developers.color = AppAppearance.highlightTextColor
      developers.colorBlendFactor = 1
      let frame1 = creditsFrames[0]
      // The amount to add to the bottom of a label's frame to align to the baseline.  I
      // don't know of a nice way to get this automatically.
      let baselineAdjust = 0.25 * attributes.fontSize
      let developerY = frame1.minY + baselineAdjust + 0.5 * developers.size.height
      let touchable = Touchable(developers, minSize: 15) { [unowned self] in self.revealDevelopers() }
      touchable.position = CGPoint(x: frame1.maxX, y: developerY)
      creditsLabels.addChild(touchable)
    }
    let wantedMidY = 0.5 * (title.frame.minY + bottomHstack.calculateAccumulatedFrame().maxY)
    // Center credits vertically at wantedMidY
    creditsLabels.position = .zero
    let creditsFrame = creditsLabels.calculateAccumulatedFrame()
    let creditsX = round(fullFrame.midX - creditsFrame.midX)
    let creditsY = round(wantedMidY - creditsFrame.midY)
    creditsLabels.position = CGPoint(x: creditsX, y: creditsY)
    credits.addChild(creditsLabels)
  }

  /// Make a new scene to display the credits
  /// - Parameter size: The size of the scene
  override init(size: CGSize) {
    os_log("CreditsScene init", log: .app, type: .debug)
    super.init(size: size)
    name = "creditsScene"
    initGameArea(avoidSafeArea: false)
    initCredits()
  }

  required init(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }

  deinit {
    os_log("CreditsScene deinit %{public}s", log: .app, type: .debug, "\(self.hash)")
  }

  // MARK: - Button actions

  /// Start a new game
  func startGame() {
    guard beginSceneSwitch() else { return }
    stopFireworks()
    switchWhenQuiescent { GameScene(size: self.fullFrame.size) }
  }

  /// Switch back to the main menu
  func mainMenu() {
    guard beginSceneSwitch() else { return }
    stopFireworks()
    switchWhenQuiescent { Globals.menuScene }
  }

  /// Show the game settings
  func showSettings() {
    guard beginSceneSwitch() else { return }
    stopFireworks()
    switchWhenQuiescent { SettingsScene(size: self.fullFrame.size) }
  }

  // MARK: - Safari

  /// Enforce pausing when showing a link via Safari
  override var forcePause: Bool { showingLink }

  /// Display a hyperlink
  /// - Parameter link: The link, minus the initial https://
  func showLink(_ link: String) {
    guard let rootVC = view?.window?.rootViewController else {
      os_log("No view controller to show %{public}s", log: .app, type: .error, link)
      return
    }
    // There's no point in a sound effect here since the scene is about to pause and
    // the effect won't have time to play
    os_log("CreditsScene will show link", log: .app, type: .debug)
    guard let url = URL(string: "https://" + link) else { fatalError("Invalid link \(link)") }
    let config = SFSafariViewController.Configuration()
    let sfvc = SFSafariViewController(url: url, configuration: config)
    sfvc.delegate = self
    isPaused = true
    showingLink = true
    rootVC.present(sfvc, animated: true)
  }

  /// This is called when the Safari is closed
  /// - Parameter sfvc: The Safari view controller
  func safariViewControllerDidFinish(_ sfvc: SFSafariViewController) {
    os_log("CreditsScene finished showing link", log: .app, type: .debug)
    showingLink = false
    isPaused = false
  }

  // MARK: - Meet the developers

  /// Make the developers show themselves
  func revealDevelopers() {
    guard let touchable = developers.parent else { return }
    let positionInPlayfield = developers.convert(.zero, to: playfield)
    developers.removeFromParent()
    touchable.removeFromParent()
    developers.position = positionInPlayfield
    playfield.addWithScaling(developers)
    let uncolorize = SKAction.colorize(withColorBlendFactor: 0, duration: 0.2)
    let texture = developers.requiredTexture()
    let grow = SKAction.scale(to: texture.size(), duration: 1)
    let totalTime = 4.0
    let rotate = SKAction.rotate(byAngle: 7 * .pi, duration: totalTime)
    let path = CGMutablePath()
    path.move(to: .zero)
    path.addCurve(to: CGPoint(x: 100, y: -300), control1: CGPoint(x: -900, y: -900), control2: CGPoint(x: -800, y: 650))
    let fly = SKAction.follow(path, asOffset: true, orientToPath: false, duration: totalTime)
    developers.run(.group([uncolorize, grow, rotate, fly])) {
      let position = self.developers.position
      let rotation = self.developers.zRotation
      self.addToPlayfield(warpOutEffect(texture: texture, position: position, rotation: rotation))
      self.developers.removeFromParent()
      self.audio.soundEffect(.ufoWarpOut, at: position)
      reportAchievement(achievement: .hideAndSeek)
    }
  }

  // MARK: - Fireworks display

  /// Create a simple firework effect
  /// - Parameters:
  ///   - color: The color of the firework (one of the UFO colors)
  ///   - duration: Amount of time for the effect
  ///   - radius: The radius of the burst
  ///   - position: The position of the burst
  /// - Returns: An `SKEmitterNode` for the effect
  func makeFirework(color: String, duration: CGFloat, radius: CGFloat, position: CGPoint) -> SKEmitterNode {
    let emitter = SKEmitterNode()
    let texture = Globals.textureCache.findTexture(imageNamed: "ufo_\(color)")
    let scale = 8 / texture.size().width
    emitter.particleTexture = texture
    emitter.particleLifetime = duration
    emitter.particleLifetimeRange = 0.25 * duration
    emitter.particleScale = scale
    emitter.particleScaleRange = 0.5 * scale
    emitter.particleScaleSpeed = -0.5 * scale / duration
    // Use more particles for a larger radius
    let averageParticles = Int(radius / 100 * 40)
    emitter.numParticlesToEmit = .random(in: averageParticles * 3 / 4 ... averageParticles * 5 / 4)
    emitter.particleBirthRate = CGFloat(emitter.numParticlesToEmit) / (0.0625 * duration)
    emitter.particleSpeed = radius / duration
    emitter.particleSpeedRange = 0.95 * emitter.particleSpeed
    emitter.particlePosition = .zero
    emitter.particlePositionRange = CGVector(dx: 10, dy: 10)
    emitter.emissionAngle = 0
    emitter.emissionAngleRange = 2 * .pi
    emitter.particleRotation = 0
    emitter.particleRenderOrder = .dontCare
    // Fade out at the end of the lifetime
    emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [1, 1, 0], times: [0, 0.85, 1])
    emitter.yAcceleration = -100
    emitter.isPaused = false
    emitter.name = "fireworkEmitter"
    emitter.position = position
    let maxLifetime = emitter.particleLifetime + 0.5 * emitter.particleLifetimeRange +
      CGFloat(emitter.numParticlesToEmit) / emitter.particleBirthRate
    emitter.run(.wait(for: Double(maxLifetime), then: .removeFromParent()))
    return emitter
  }

  /// Create a firework effect
  ///
  /// This may either return a simple effect or a compound effect made from different
  /// colors and burst radii.
  ///
  /// - Parameter position: The position of the firework
  /// - Returns: An array of nodes for the effect
  func makeFirework(position: CGPoint) -> [SKNode] {
    let colors = ["green", "blue", "red"]
    let index1 = Int.random(in: 0 ..< colors.count)
    let radius1 = CGFloat.random(in: 150 ... 200)
    let duration = CGFloat.random(in: 1.2 ... 1.5)
    if Bool.random() {
      return [makeFirework(color: colors[index1], duration: duration, radius: radius1, position: position)]
    } else {
      let index2 = (index1 + (Bool.random() ? 1 : 2)) % colors.count
      let radius2 = CGFloat.random(in: 100 ... 150)
      return [makeFirework(color: colors[index1], duration: duration, radius: radius1, position: position),
              makeFirework(color: colors[index2], duration: duration, radius: radius2, position: position)]
    }
  }

  /// Set off a burst of fireworks
  ///
  /// This method constantly reschedules itself until stopped by `stopFireworks`
  func fireworks() {
    let topArea = fullFrame.divided(atDistance: 0.33 * fullFrame.height, from: .minYEdge).remainder
    let fireworkArea = topArea.insetBy(dx: 100, dy: 50)
    let burstPoint = CGPoint(x: .random(in: fireworkArea.minX ... fireworkArea.maxX),
                             y: .random(in: fireworkArea.minY ... fireworkArea.maxY))
    addToPlayfield(makeFirework(position: burstPoint))
    let sounds = [SoundEffect.firework1, .firework2, .firework3, .firework4]
    audio.soundEffect(sounds.randomElement()!, at: burstPoint)
    if Int.random(in: 0 ..< 4) == 0 {
      // On occasion, do a burst.  The chance here is chosen to make strings of three
      // unusual but not so uncommon that they never see one.
      run(.wait(for: .random(in: 0.1 ... 0.4), then: fireworks), withKey: "fireworks")
    } else {
      // Most commonly do just a single firework
      run(.wait(for: .random(in: 2 ... 3), then: fireworks), withKey: "fireworks")
    }
  }

  /// Stop the fireworks display
  func stopFireworks() {
    removeAction(forKey: "fireworks")
  }

  /// Start the fireworks display
  /// - Parameter view: The view that will present the scene
  override func didMove(to view: SKView) {
    super.didMove(to: view)
    // I think it's more effective to have this delay a bit longer than the normal
    // delay between bursts.  The first time that they see the credits, it gives them
    // a moment to think that it's a normal static scene before the show begins.
    run(.wait(for: .random(in: 4 ... 5), then: fireworks), withKey: "fireworks")
  }

  override func update(_ currentTime: TimeInterval) {
    super.update(currentTime)
    endOfUpdate()
  }
}
