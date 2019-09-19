//
//  BasicScene.swift
//  Asteroids
//
//  Created by David Long on 7/7/19.
//  Copyright © 2019 David Long. All rights reserved.
//

import SpriteKit

enum LevelZs: CGFloat {
  case background = -200
  case stars = -100
  case playfield = 0
  case controls = 100
  case info = 200
}

enum ObjectCategories: UInt32 {
  case player = 1
  case playerShot = 2
  case asteroid = 4
  case ufo = 8
  case ufoShot = 16
  case fragment = 32
  case offScreen = 32768
}

extension SKPhysicsBody {
  func isA(_ category: ObjectCategories) -> Bool {
    return (categoryBitMask & category.rawValue) != 0
  }

  func isOneOf(_ categories: UInt32) -> Bool {
    return (categoryBitMask & categories) != 0
  }

  var isOnScreen: Bool {
    get { return categoryBitMask & ObjectCategories.offScreen.rawValue == 0 }
    set { if newValue {
      categoryBitMask &= ~ObjectCategories.offScreen.rawValue
      } else {
      categoryBitMask |= ObjectCategories.offScreen.rawValue
      }
    }
  }
}

func setOf(_ categories: [ObjectCategories]) -> UInt32 {
  return categories.reduce(0) { $0 | $1.rawValue }
}

func RGB(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
  return UIColor(red: CGFloat(red)/255.0, green: CGFloat(green)/255.0, blue: CGFloat(blue)/255.0, alpha: 1.0)
}

extension SKNode {
  func wait(for time: Double, then action: SKAction) {
    run(SKAction.sequence([SKAction.wait(forDuration: time), action]))
  }

  func wait(for time: Double, then action: @escaping (() -> Void)) {
    wait(for: time, then: SKAction.run(action))
  }

  func requiredPhysicsBody() -> SKPhysicsBody {
    let printName = name ?? "<unknown name>"
    guard let body = physicsBody else { fatalError("Node \(printName) is missing a physics body") }
    return body
  }
}

extension Globals {
  static var lastUpdateTime = 0.0
}

class BasicScene: SKScene, SKPhysicsContactDelegate {
  var fullFrame: CGRect!
  let textColor = RGB(101, 185, 240)
  let highlightTextColor = RGB(246, 205, 68)
  let buttonColor = RGB(137, 198, 79)
  var gameFrame: CGRect!
  var gameArea = SKCropNode()
  var playfield: Playfield!
  var safeAreaLeft = CGFloat(0.0)
  var safeAreaRight = CGFloat(0.0)
  var asteroids = Set<SKSpriteNode>()
  var ufos = Set<UFO>()

  func makeSprite(imageNamed name: String, initializer: ((SKSpriteNode) -> Void)? = nil) -> SKSpriteNode {
    return Globals.spriteCache.findSprite(imageNamed: name, initializer: initializer)
  }

  func recycleSprite(_ sprite: SKSpriteNode) {
    // Speed may have been altered by the slow-motion effect in the playfield.  Be
    // sure that when we give back the recycled sprite for a new object that the
    // speed is reset to the default 1.
    sprite.speed = 1
    Globals.spriteCache.recycleSprite(sprite)
  }

  func tilingShader(forTexture texture: SKTexture) -> SKShader {
    // Do not to assume that the texture has v_tex_coord ranging in (0, 0) to (1, 1)!
    // If the texture is part of a texture atlas, this is not true.  Since we only
    // use this for a particular texture, we just pass in the texture and hard-code
    // the required v_tex_coord transformations.  For this case, the INPUT
    // v_tex_coord is from (0,0) to (1,1), since it corresponds to the coordinates in
    // the shape node that we're tiling.  The OUTPUT v_tex_coord has to be in the
    // space of the texture, so it needs a scale and shift.
    let rect = texture.textureRect()
    let shaderSource = """
    void main() {
      vec2 scaled = v_tex_coord * a_repetitions;
      // rot is 0...3 and a repetion is rotated 90*rot degrees.  That
      // helps avoid any obvious patterning in this case.
      int rot = (int(scaled.x) + int(scaled.y)) & 0x3;
      v_tex_coord = fract(scaled);
      if (rot == 1) v_tex_coord = vec2(1.0 - v_tex_coord.y, v_tex_coord.x);
      else if (rot == 2) v_tex_coord = vec2(1.0) - v_tex_coord;
      else if (rot == 3) v_tex_coord = vec2(v_tex_coord.y, 1.0 - v_tex_coord.x);
      // Transform from (0,0)-(1,1)
      v_tex_coord *= vec2(\(rect.size.width), \(rect.size.height));
      v_tex_coord += vec2(\(rect.origin.x), \(rect.origin.y));
      gl_FragColor = SKDefaultShading();
    }
    """
    let shader = SKShader(source: shaderSource)
    shader.attributes = [SKAttribute(name: "a_repetitions", type: .vectorFloat2)]
    return shader
  }

  func initBackground() {
    let background = SKShapeNode(rect: gameFrame)
    background.name = "background"
    background.strokeColor = .clear
    background.blendMode = .replace
    background.zPosition = LevelZs.background.rawValue
    let stars = Globals.textureCache.findTexture(imageNamed: "starfield_blue")
    let tsize = stars.size()
    background.fillTexture = stars
    background.fillColor = .white
    background.fillShader = tilingShader(forTexture: stars)
    let reps = vector_float2([Float(gameFrame.width / tsize.width), Float(gameFrame.height / tsize.height)])
    background.setValue(SKAttributeValue(vectorFloat2: reps), forAttribute: "a_repetitions")
    gameArea.addChild(background)
  }

  func twinkleAction(period: Double, from dim: CGFloat, to bright: CGFloat) -> SKAction {
    let twinkleDuration = 0.4
    let delay = SKAction.wait(forDuration: period - twinkleDuration)
    let brighten = SKAction.fadeAlpha(to: bright, duration: 0.5 * twinkleDuration)
    brighten.timingMode = .easeIn
    let fade = SKAction.fadeAlpha(to: dim, duration: 0.5 * twinkleDuration)
    fade.timingMode = .easeOut
    return SKAction.repeatForever(SKAction.sequence([brighten, fade, delay]))
  }

  func makeStar() -> SKSpriteNode {
    let tints = [RGB(202, 215, 255),
                 RGB(248, 247, 255),
                 RGB(255, 244, 234),
                 RGB(255, 210, 161),
                 RGB(255, 204, 111)]
    let tint = tints.randomElement()!
    let texture = Globals.textureCache.findTexture(imageNamed: "star1")
    let star = SKSpriteNode(texture: texture, size: texture.size().scale(by: .random(in: 0.5...1.0)))
    star.name = "star"
    star.color = tint
    star.colorBlendFactor = 1.0
    return star
  }

  func initStars() {
    let stars = SKNode()
    stars.name = "stars"
    stars.zPosition = LevelZs.stars.rawValue
    gameArea.addChild(stars)
    let dim = CGFloat(0.1)
    let bright = CGFloat(0.3)
    let period = 8.0
    let twinkle = twinkleAction(period: period, from: dim, to: bright)
    for _ in 0..<100 {
      let star = makeStar()
      star.alpha = dim
      var minSep = CGFloat(0)
      let wantedSep = 3 * star.size.diagonal()
      while minSep < wantedSep {
        minSep = .infinity
        star.position = CGPoint(x: .random(in: gameFrame.minX...gameFrame.maxX),
                                y: .random(in: gameFrame.minY...gameFrame.maxY))
        for otherStar in stars.children {
          minSep = min(minSep, (otherStar.position - star.position).norm2())
        }
      }
      star.wait(for: .random(in: 0.0...period), then: twinkle)
      star.speed = .random(in: 0.75...1.5)
      stars.addChild(star)
    }
  }

  func initPlayfield() {
    playfield = Playfield(bounds: gameFrame)
    playfield.zPosition = LevelZs.playfield.rawValue
    gameArea.addChild(playfield)
  }

  func setPositionsForSafeArea() {
    // Subclasses that need to do something when the safe area changes should
    // override this.
    logging("setPositionsForSafeArea called")
  }

  func maybeResizeGameFrame() {
    // This is used to set the gameFrame in response to notifications about the safe
    // area.
    guard safeAreaLeft != 0 || safeAreaRight != 0 else {
      gameFrame = fullFrame
      gameArea.maskNode = nil
      return
    }
    let gameAreaWidth = size.width - (safeAreaLeft + safeAreaRight)
    logging("maybeResizeGameFrame using width \(gameAreaWidth)")
    gameFrame = CGRect(x: -0.5 * gameAreaWidth, y: -0.5 * size.height, width: gameAreaWidth, height: size.height)
    let mask = SKShapeNode(rect: gameFrame)
    mask.fillColor = .white
    mask.strokeColor = .clear
    gameArea.maskNode = mask
  }

  func setSafeArea(left: CGFloat, right: CGFloat) {
    logging("setSafeArea called with \(left) and \(right)")
    safeAreaLeft = left
    safeAreaRight = right
    maybeResizeGameFrame()
    setPositionsForSafeArea()
  }

  func initGameArea(limitAspectRatio: Bool) {
    let aspect = size.width / size.height
    if aspect < 1.6 || !limitAspectRatio {
      // Playfield will fill the complete frame.
      gameFrame = fullFrame
    } else {
      // This is probably a phone.  We may want to limit the aspect ratio, but even
      // if not there might be a nontrivial safe area.
      maybeResizeGameFrame()
    }
    gameArea.name = "gameArea"
    addChild(gameArea)
    initBackground()
    initStars()
    initPlayfield()
  }

  func initSounds() {
    Globals.sounds.stereoEffectsFrame = gameFrame
  }
  
  func fireUFOLaser(angle: CGFloat, position: CGPoint, speed: CGFloat) {
    let laser = Globals.spriteCache.findSprite(imageNamed: "lasersmall_red") { sprite in
      guard let texture = sprite.texture else { fatalError("Where is the laser texture?") }
      let ht = texture.size().height
      let body = SKPhysicsBody(circleOfRadius: 0.5 * ht,
                               center: CGPoint(x: 0.5 * (texture.size().width - ht), y: 0))
      body.allowsRotation = false
      body.linearDamping = 0
      body.categoryBitMask = ObjectCategories.ufoShot.rawValue
      body.collisionBitMask = 0
      body.contactTestBitMask = setOf([.asteroid, .player])
      sprite.physicsBody = body
      sprite.zPosition = -1
    }
    laser.wait(for: Double(0.9 * gameFrame.height / speed)) { self.removeUFOLaser(laser) }
    playfield.addWithScaling(laser)
    laser.position = position
    laser.zRotation = angle
    laser.requiredPhysicsBody().velocity = CGVector(angle: angle).scale(by: speed)
    Globals.sounds.soundEffect(.ufoShot, at: position)
  }
  
  func removeUFOLaser(_ laser: SKSpriteNode) {
    assert(laser.name == "lasersmall_red")
    laser.removeAllActions()
    recycleSprite(laser)
  }
  
  func makeAsteroid(position pos: CGPoint, size: String, velocity: CGVector, onScreen: Bool) {
    let typesForSize = ["small": 2, "med": 2, "big": 4, "huge": 3]
    guard let numTypes = typesForSize[size] else { fatalError("Incorrect asteroid size") }
    var type = Int.random(in: 1...numTypes)
    if Int.random(in: 1...4) != 1 {
      // Prefer the last type for each size (where we can use a circular physics
      // body), rest just for variety.
      type = numTypes
    }
    let name = "meteor\(size)\(type)"
    let asteroid = Globals.spriteCache.findSprite(imageNamed: name) { sprite in
      guard let texture = sprite.texture else { fatalError("Where is the asteroid texture?") }
      // Huge and big asteroids of all types except the default have irregular shape,
      // so we use a pixel-perfect physics body for those.  Everything else gets a
      // circle.
      let body = (type == numTypes || size == "med" || size == "small" ?
        SKPhysicsBody(circleOfRadius: 0.5 * texture.size().width) :
        SKPhysicsBody(texture: texture, size: texture.size()))
      body.angularDamping = 0
      body.linearDamping = 0
      body.categoryBitMask = ObjectCategories.asteroid.rawValue
      body.collisionBitMask = 0
      body.contactTestBitMask = setOf([.player, .playerShot, .ufo, .ufoShot])
      body.restitution = 0.9
      sprite.physicsBody = body
    }
    asteroid.position = pos
    let minSpeed = Globals.gameConfig.asteroidMinSpeed
    let maxSpeed = Globals.gameConfig.asteroidMaxSpeed
    var finalVelocity = velocity
    let speed = velocity.norm2()
    if speed == 0 {
      finalVelocity = CGVector(angle: .random(in: 0 ... 2 * .pi)).scale(by: .random(in: minSpeed...maxSpeed))
    } else if speed < minSpeed {
      finalVelocity = velocity.scale(by: minSpeed / speed)
    } else if speed > maxSpeed {
      finalVelocity = velocity.scale(by: maxSpeed / speed)
    }
    // Important: addChild must be done BEFORE setting the velocity.  If it's after,
    // then the addChild mucks with the velocity a little bit, which is totally
    // bizarre and also can totally screw us up.  If the asteroid is being spawned,
    // we've calculated the initial position and velocity so that it will get onto
    // the screen, but if the velocity gets tweaked, then that guarantee is out the
    // window.
    playfield.addWithScaling(asteroid)
    let body = asteroid.requiredPhysicsBody()
    body.velocity = finalVelocity
    body.isOnScreen = onScreen
    body.angularVelocity = .random(in: -.pi ... .pi)
    asteroids.insert(asteroid)
  }

  func spawnAsteroid(size: String) {
    // Initial direction of the asteroid from the center of the screen
    let dir = CGVector(angle: .random(in: -.pi ... .pi))
    // Traveling towards the center at a random speed
    let minSpeed = Globals.gameConfig.asteroidMinSpeed
    let maxSpeed = Globals.gameConfig.asteroidMaxSpeed
    let speed = CGFloat.random(in: minSpeed ... max(min(4 * minSpeed, 0.33 * maxSpeed), 0.25 * maxSpeed))
    let velocity = dir.scale(by: -speed)
    // Offset from the center by some random amount
    let offset = CGPoint(x: .random(in: 0.75 * gameFrame.minX...0.75 * gameFrame.maxX),
                         y: .random(in: 0.75 * gameFrame.minY...0.75 * gameFrame.maxY))
    // Find a random distance that places us beyond the screen by a reasonable amount
    var dist = .random(in: 0.25...0.5) * gameFrame.height
    let minExclusion = max(1.25 * speed, 50)
    let maxExclusion = max(5 * speed, 200)
    let exclusion = -CGFloat.random(in: minExclusion...maxExclusion)
    while gameFrame.insetBy(dx: exclusion, dy: exclusion).contains(offset + dir.scale(by: dist)) {
      dist *= 1.5
    }
    makeAsteroid(position: offset + dir.scale(by: dist), size: size, velocity: velocity, onScreen: false)
  }

  func asteroidRemoved() {
    // Subclasses should override this to do additional work or checks when an
    // asteroid is removed.  E.g., GameScene would see if there are no more
    // asteroids, and if not, spawn a new wave.
  }

  func removeAsteroid(_ asteroid: SKSpriteNode) {
    recycleSprite(asteroid)
    asteroids.remove(asteroid)
    asteroidRemoved()
  }

  func removeAllAsteroids() {
    // For clearing out the playfield when starting a new game
    asteroids.forEach {
      $0.removeFromParent()
      recycleSprite($0)
    }
    asteroids.removeAll()
  }

  func addEmitter(_ emitter: SKEmitterNode) {
    emitter.name = "emitter"
    let maxParticleLifetime = emitter.particleLifetime + 0.5 * emitter.particleLifetimeRange
    let maxEmissionTime = CGFloat(emitter.numParticlesToEmit) / emitter.particleBirthRate
    let maxTotalTime = Double(maxEmissionTime + maxParticleLifetime)
    emitter.zPosition = 1
    emitter.wait(for: maxTotalTime, then: SKAction.removeFromParent())
    emitter.isPaused = false
    playfield.addWithScaling(emitter)
  }

  func makeAsteroidSplitEffect(_ asteroid: SKSpriteNode, ofSize size: Int) {
    let emitter = SKEmitterNode()
    emitter.particleTexture = Globals.textureCache.findTexture(imageNamed: "meteorsmall1")
    let effectDuration = CGFloat(0.25)
    emitter.particleLifetime = effectDuration
    emitter.particleLifetimeRange = 0.15 * effectDuration
    emitter.particleScale = 0.75
    emitter.particleScaleRange = 0.25
    emitter.numParticlesToEmit = 4 * size
    emitter.particleBirthRate = CGFloat(emitter.numParticlesToEmit) / (0.25 * effectDuration)
    let radius = 0.75 * asteroid.texture!.size().width
    emitter.particleSpeed = radius / effectDuration
    emitter.particleSpeedRange = 0.25 * emitter.particleSpeed
    emitter.particlePosition = .zero
    emitter.particlePositionRange = CGVector(dx: radius, dy: radius).scale(by: 0.25)
    emitter.emissionAngle = 0
    emitter.emissionAngleRange = 2 * .pi
    emitter.particleRotation = 0
    emitter.particleRotationRange = .pi
    emitter.particleRotationSpeed = 2 * .pi / effectDuration
    emitter.position = asteroid.position
    addEmitter(emitter)
  }

  func splitAsteroid(_ asteroid: SKSpriteNode) {
    let sizes = ["small", "med", "big", "huge"]
    let hitEffect: [SoundEffect] = [.asteroidSmallHit, .asteroidMedHit, .asteroidBigHit, .asteroidHugeHit]
    guard let size = (sizes.firstIndex { asteroid.name!.contains($0) }) else {
      fatalError("Asteroid not of recognized size")
    }
    let velocity = asteroid.requiredPhysicsBody().velocity
    let pos = asteroid.position
    makeAsteroidSplitEffect(asteroid, ofSize: size)
    Globals.sounds.soundEffect(hitEffect[size], at: pos)
    // Don't split med or small asteroids.  Size progression should go huge -> big -> med,
    // but we include small just for completeness in case we change our minds later.
    if size >= 2 {
      // Choose a random direction for the first child and project to get that child's velocity
      let velocity1Angle = CGVector(angle: velocity.angle() + .random(in: -0.4 * .pi...0.4 * .pi))
      // Throw in a random scaling just to keep it from being too uniform
      let velocity1 = velocity.project(unitVector: velocity1Angle).scale(by: .random(in: 0.75 ... 1.25))
      // The second child's velocity is chosen from momentum conservation
      let velocity2 = velocity.scale(by: 2) - velocity1
      // Add a bit of extra spice just to keep the player on their toes
      let oomph = Globals.gameConfig.value(for: \.asteroidSpeedBoost)
      makeAsteroid(position: pos, size: sizes[size - 1], velocity: velocity1.scale(by: oomph), onScreen: true)
      makeAsteroid(position: pos, size: sizes[size - 1], velocity: velocity2.scale(by: oomph), onScreen: true)
    }
    removeAsteroid(asteroid)
  }

  func addExplosion(_ pieces: [SKNode]) {
    for p in pieces {
      playfield.addWithScaling(p)
    }
  }

  func warpOutUFOs() -> Double {
    // This is a little involved, but here's the idea.  The player has just died and
    // we've delayed a bit to let any of his existing shots hit stuff.  After the
    // shots are gone, any remaining UFOs will warp out before the player respawns or
    // we show GAME OVER.  We warp out the UFOs by having each run an action that
    // waits for a random delay before calling ufo.warpOut.  While the UFO is
    // delaying though, it might hit an asteroid and be destroyed, so the action has
    // a "warpOut" key through which we can cancel it.  This function returns the
    // maximum warpOut delay for all the UFOs; respawnOrGameOver will wait a bit
    // longer than that before triggering whatever it's going to do.
    //
    // One further caveat...
    //
    // When a UFO gets added by spawnUFO, it's initially way off the playfield, but
    // its audio will start so as to give the player a chance to prepare.  After a
    // second, an action will trigger to launch the UFO.  It gets moved to just off
    // the screen and its velocity is set so that it will move and become visible,
    // and as soon as isOnScreen becomes true, it will start flying normally.  For
    // warpOuts of these UFOs, everything will happen as you expect with the usual
    // animations.  However, for a UFO that has been spawned but not yet launched, we
    // still want warpOutUFOs to get rid of it.  These we'll just nuke immediately,
    // but be sure to call their cleanup method to give them a chance to do any
    // housekeeping that they may need.
    var maxDelay = 0.0
    ufos.forEach { ufo in
      if ufo.requiredPhysicsBody().isOnScreen {
        let delay = Double.random(in: 0.5...1.5)
        maxDelay = max(maxDelay, delay)
        ufo.run(SKAction.sequence([
          SKAction.wait(forDuration: delay),
          SKAction.run({
            self.ufos.remove(ufo)
            Globals.sounds.soundEffect(.ufoWarpOut, at: ufo.position)
            let effects = ufo.warpOut()
            self.playfield.addWithScaling(effects[0])
            self.playfield.addWithScaling(effects[1])
          })]), withKey: "warpOut")
      } else {
        logging("Cleanup on unlaunched ufo")
        ufo.cleanup()
        ufos.remove(ufo)
      }
    }
    return maxDelay
  }

  func spawnUFO(ufo: UFO) {
    playfield.addWithScaling(ufo)
    ufos.insert(ufo)
    // Position the UFO just off the screen on one side or another.  We set the side
    // here so that the positional audio will give a clue about where it's coming
    // from.  Actual choice of Y position and beginning of movement happens after a
    // delay.
    let ufoSize = 0.6 * ufo.size.diagonal()
    let x = (Bool.random() ? gameFrame.maxX + ufoSize : gameFrame.minX - ufoSize)
    // Audio depends only on left/right, i.e., x.  We have the y way off in the
    // distance to avoid potential collisions in the time before launch.
    ufo.position = CGPoint(x: x, y: -1e9)
    wait(for: 1) { self.launchUFO(ufo) }
  }
  
  func launchUFO(_ ufo: UFO) {
    let ufoRadius = 0.5 * ufo.size.diagonal()
    // Try to find a safe spawning position, but if we can't find one after some
    // number of tries, just go ahead and spawn anyway.
    var bestPosition: CGPoint? = nil
    var bestClearance = CGFloat.infinity
    for _ in 0..<10 {
      let pos = CGPoint(x: ufo.position.x, y: .random(in: 0.9 * gameFrame.minY ... 0.9 * gameFrame.maxY))
      var thisClearance = CGFloat.infinity
      for asteroid in asteroids {
        let bothRadii = ufoRadius + 0.5 * asteroid.size.diagonal()
        thisClearance = min(thisClearance, (asteroid.position - pos).norm2() - bothRadii)
        // Check the wrapped position too
        thisClearance = min(thisClearance, (asteroid.position - CGPoint(x: -pos.x, y: pos.y)).norm2() - bothRadii)
      }
      if bestPosition == nil || thisClearance > bestClearance {
        bestPosition = pos
        bestClearance = thisClearance
      }
      if bestClearance > 5 * ufoRadius {
        break
      }
    }
    ufo.position = bestPosition!
    let body = ufo.requiredPhysicsBody()
    body.isDynamic = true
    body.velocity = CGVector(dx: copysign(ufo.currentSpeed, -ufo.position.x), dy: 0)
  }
  
  func destroyUFO(_ ufo: UFO) {
    // If the player was destroyed earlier, the UFO will have been scheduled for
    // warpOut.  But if it just got destroyed (by hitting an asteroid) we have to be
    // sure to cancel the warp.
    ufo.removeAction(forKey: "warpOut")
    ufos.remove(ufo)
    Globals.sounds.soundEffect(.ufoExplosion, at: ufo.position)
    addExplosion(ufo.explode())
  }

  func ufoLaserHit(laser: SKNode, asteroid: SKNode) {
    removeUFOLaser(laser as! SKSpriteNode)
    splitAsteroid(asteroid as! SKSpriteNode)
  }

  func ufoCollided(ufo: SKNode, asteroid: SKNode) {
    splitAsteroid(asteroid as! SKSpriteNode)
    destroyUFO(ufo as! UFO)
  }

  func when(_ contact: SKPhysicsContact,
            isBetween type1: ObjectCategories, and type2: ObjectCategories,
            action: (SKNode, SKNode) -> Void) {
    let b1 = contact.bodyA
    let b2 = contact.bodyB
    guard let node1 = contact.bodyA.node, node1.parent != nil else { return }
    guard let node2 = contact.bodyB.node, node2.parent != nil else { return }
    if b1.isA(type1) && b2.isA(type2) {
      action(node1, node2)
    } else if b2.isA(type1) && b1.isA(type2) {
      action(node2, node1)
    }
  }

  func switchScene(to newScene: SKScene) {
    logging("\(name!) switchScene to \(newScene.name!)")
    let transitionColor = RGB(43, 45, 50)
    let transition = SKTransition.fade(with: transitionColor, duration: 1)
    newScene.removeAllActions()
    logging("\(name!) about to call presentScene")
    view?.presentScene(newScene, transition: transition)
    logging("\(name!) finished presentScene")
  }

  // Subclasses should provide a didBegin method and set themselves as the
  // contactDelegate for physicsWorld.  E.g.
  //
  //  func didBegin(_ contact: SKPhysicsContact) {
  //    when(contact, isBetween: .ufoShot, and: .asteroid) { ufoLaserHit(laser: $0, asteroid: $1)}
  //    when(contact, isBetween: .ufo, and: .asteroid) { ufoCollided(ufo: $0, asteroid: $1) }
  //    ...
  //  }
  //
  // They should also provide an update method with their own frame logic, e.g.,
  //
  //  override func update(_ currentTime: TimeInterval) {
  //    super.update(currentTime)
  //    ufos.forEach {
  //      $0.fly(player: player, playfield: playfield) {
  //        (angle, position, speed) in self.fireUFOLaser(angle: angle, position: position, speed: speed)
  //      }
  //    }
  //    playfield.wrapCoordinates()
  //    ...
  //  }
  override func update(_ currentTime: TimeInterval) {
    super.update(currentTime)
    Globals.lastUpdateTime = currentTime
    logging("\(name!) update", "time \(currentTime)")
  }

  // The initializers should also be overridden by subclasses, but be sure to call
  // super.init()
  override required init(size: CGSize) {
    super.init(size: size)
    fullFrame = CGRect(x: -0.5 * size.width, y: -0.5 * size.height, width: size.width, height: size.height)
    scaleMode = .aspectFill
    anchorPoint = CGPoint(x: 0.5, y: 0.5)
    physicsWorld.gravity = .zero
  }

  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented by BasicScene")
  }

  // Subclasses should override these too, typically to do something like starting a
  // new game or showing a menu.  When debugging, messages can go here.
  override func didMove(to view: SKView) {
    logging("\(name!) didMove to view")
  }

  override func willMove(from view: SKView) {
    logging("\(name!) willMove from view")
    removeAllActions()
  }
}
