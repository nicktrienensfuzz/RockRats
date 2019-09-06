//
//  UFO.swift
//  Asteroids
//
//  Created by Daniel on 8/22/19.
//  Copyright © 2019 David Long. All rights reserved.
//

import SpriteKit

func aim(at p: CGVector, targetVelocity v: CGFloat, shotSpeed s: CGFloat) -> CGFloat? {
  let a = s * s - v * v
  let b = -2 * p.dx * v
  let c = -p.dx * p.dx - p.dy * p.dy
  let discriminant = b * b - 4 * a * c
  guard discriminant >= 0 else { return nil }
  let r = sqrt(discriminant)
  let solutionA = (-b - r) / (2 * a)
  let solutionB = (-b + r) / (2 * a)
  if solutionA >= 0 && solutionB >= 0 { return min(solutionA, solutionB) }
  if solutionA < 0 && solutionB < 0 { return nil }
  return max(solutionA, solutionB)
}

func aim(at p: CGVector, targetVelocity v: CGVector, shotSpeed s: CGFloat) -> CGFloat? {
  let theta = v.angle()
  return aim(at: p.rotate(by: -theta), targetVelocity: v.norm2(), shotSpeed: s)
}

class UFO: SKNode {
  let isBig: Bool
  let ufoTexture: SKTexture
  var currentSpeed: CGFloat
  var engineSounds: SKAudioNode
  let meanShotTime: Double
  var delayOfFirstShot: Double
  var shootingEnabled = false
  var shotAccuracy: CGFloat
  let warpTime = 0.5
  let warpOutShader: SKShader

  required init(sounds: Sounds, brothersKilled: Int) {
    isBig = .random(in: 0...1) >= Globals.gameConfig.value(for: \.smallUFOChance)
    ufoTexture = Globals.textureCache.findTexture(imageNamed: isBig ? "ufo_green" : "ufo_red")
    self.engineSounds = sounds.audioNodeFor(isBig ? .ufoEnginesBig : .ufoEnginesSmall)
    self.engineSounds.autoplayLooped = true
    self.engineSounds.run(SKAction.changeVolume(to: 0.5, duration: 0))
    sounds.addChild(self.engineSounds)
    let maxSpeed = Globals.gameConfig.value(for: \.ufoMaxSpeed)[isBig ? 0 : 1]
    currentSpeed = .random(in: 0.5 * maxSpeed ... maxSpeed)
    let revengeFactor = max(brothersKilled - 3, 0)
    // When delayOfFirstShot is nonnegative, it means that the UFO hasn't gotten on
    // to the screen yet.  When it appears, we schedule an action after that delay to
    // enable firing.  When revenge factor starts increasing, the UFOs start shooting
    // faster, getting much quicker on the draw initially, and being much more
    // accurate in their shooting.
    meanShotTime = Globals.gameConfig.value(for: \.ufoMeanShotTime)[isBig ? 0 : 1] * pow(0.75, Double(revengeFactor))
    delayOfFirstShot = Double.random(in: 0 ... meanShotTime * pow(0.75, Double(revengeFactor)))
    shotAccuracy = Globals.gameConfig.value(for: \.ufoAccuracy)[isBig ? 0 : 1] * pow(0.75, CGFloat(revengeFactor))
    warpOutShader = fanFoldShader(forTexture: ufoTexture, warpTime: warpTime)
    super.init()
    name = "ufo"
    let ufo = SKSpriteNode(texture: ufoTexture)
    ufo.name = "ufoImage"
    addChild(ufo)
    let body = SKPhysicsBody(circleOfRadius: 0.5 * ufoTexture.size().width)
    body.mass = isBig ? 1 : 0.75
    body.categoryBitMask = ObjectCategories.ufo.rawValue
    body.collisionBitMask = 0
    body.contactTestBitMask = setOf([.asteroid, .player, .playerShot])
    body.linearDamping = 0
    body.angularDamping = 0
    body.restitution = 0.9
    body.isOnScreen = false
    body.isDynamic = false
    body.angularVelocity = .pi * 2
    physicsBody = body
  }
  
  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented by UFO")
  }

  func fly(player: Ship, playfield: Playfield, addLaser: ((CGFloat, CGPoint, CGFloat) -> Void)) {
    guard parent != nil else { return }
    guard let bounds = scene?.frame else { return }
    let body = requiredPhysicsBody()
    guard body.isOnScreen else { return }
    if delayOfFirstShot >= 0 {
      // Just moved onto the screen, enable shooting after a delay
      wait(for: delayOfFirstShot) { self.shootingEnabled = true }
      delayOfFirstShot = -1
    }
    let maxSpeed = Globals.gameConfig.value(for: \.ufoMaxSpeed)[isBig ? 0 : 1]
    if Int.random(in: 0...100) == 0 {
      currentSpeed = .random(in: 0.3 * maxSpeed ... maxSpeed)
      body.angularVelocity = copysign(.pi * 2, -body.angularVelocity)
    }
    let ourRadius = 0.5 * size.diagonal()
    let forceScale = Globals.gameConfig.value(for: \.ufoDodging) * 1000
    let shotAnticipation = Globals.gameConfig.value(for: \.ufoShotAnticipation)
    var totalForce = CGVector.zero
    let interesting = (shotAnticipation > 0 ?
      setOf([.asteroid, .player, .playerShot]) :
      setOf([.asteroid, .player]))
    // By default, shoot at the player.  If there's an asteroid that's notably closer
    // though, shoot that instead.  In addition to the revenge factor increase in UFO
    // danger, that helps ensure that the player can't sit around and farm UFOs for
    // points forever.
    var potentialTarget: SKNode? = (player.parent != nil ? player : nil)
    var targetDistance = CGFloat.infinity
    var playerDistance = CGFloat.infinity
    let interestingDistance = 0.33 * min(bounds.width, bounds.height)
    for node in playfield.children {
      // Be sure not to consider off-screen things.  That happens if the last asteroid is
      // destroyed while the UFO is flying around and a new wave spawns.
      guard let body = node.physicsBody, body.isOnScreen else { continue }
      if body.isOneOf(interesting) {
        // This can maybe be done better.  We need to think about how to do the
        // different cases more fluidly rather than in one big loop with a bunch of
        // conditionals for the different types.
        let dx1 = node.position.x - position.x
        let dx2 = copysign(bounds.width, -dx1) + dx1
        let dx = (abs(dx1) < abs(dx2) ? dx1 : dx2)
        let dy1 = node.position.y - position.y
        let dy2 = copysign(bounds.height, -dy1) + dy1
        let dy = (abs(dy1) < abs(dy2) ? dy1 : dy2)
        // The + 5 is because of possible wrapping hysteresis
        assert(abs(dx) <= bounds.width / 2 + 5 && abs(dy) <= bounds.height / 2 + 5)
        var r = CGVector(dx: dx, dy: dy)
        if body.isA(.playerShot) {
          // Shots travel fast, so emphasize dodging to the side.  We do this by projecting out
          // some of the displacement along the direction of the shot.
          let vhat = body.velocity.scale(by: 1 / body.velocity.norm2())
          r = r - r.project(unitVector: vhat).scale(by: shotAnticipation)
        }
        var d = r.norm2()
        // Ignore stuff that's too far away
        guard d <= interestingDistance else { continue }
        var objectRadius = CGFloat(0)
        if body.isA(.asteroid) {
          objectRadius = 0.5 * (node as! SKSpriteNode).size.diagonal()
        } else if body.isA(.player) {
          objectRadius = 0.5 * (node as! Ship).size.diagonal()
          playerDistance = d
        }
        if d < targetDistance {
          potentialTarget = node
          targetDistance = d
        }
        d -= ourRadius + objectRadius
        // Limit the force so that we don't poke the UFO by an enormous amount
        let dmin = CGFloat(20)
        let dlim = 0.5 * (sqrt((d - dmin) * (d - dmin) + dmin) + d)
        totalForce = totalForce + r.scale(by: -forceScale / (dlim * dlim))
      }
    }
    body.applyForce(totalForce)
    if body.velocity.norm2() > currentSpeed {
      body.velocity = body.velocity.scale(by: 0.95)
    }
    else if body.velocity.norm2() < currentSpeed {
      body.velocity = body.velocity.scale(by: 1.05)
    }
    if body.velocity.norm2() > maxSpeed {
      body.velocity = body.velocity.scale(by: maxSpeed / body.velocity.norm2())
    }
    if playerDistance < 1.5 * targetDistance || (player.parent != nil && Int.random(in: 0..<100) >= 25) {
      // Override closest-object targetting if the player is about at the same
      // distance.  Also bias towards randomly shooting at the player even if they're
      // pretty far.
      potentialTarget = player
    }
    guard let target = potentialTarget, shootingEnabled else { return }
    let shotSpeed = Globals.gameConfig.value(for: \.ufoShotSpeed)[isBig ? 0 : 1]
    guard var angle = aimAt(target, shotSpeed: shotSpeed) else { return }
    if target != player {
      // If we're targetting an asteroid, be pretty accurate
      angle += CGFloat.random(in: -0.1 * shotAccuracy * .pi ... 0.1 * shotAccuracy * .pi)
    } else {
      angle += CGFloat.random(in: -shotAccuracy * .pi ... shotAccuracy * .pi)
    }
    shotAccuracy *= 0.97  // Gunner training ;-)
    let shotDirection = CGVector(angle: angle)
    let shotPosition = position + shotDirection.scale(by: 0.5 * ufoTexture.size().width)
    addLaser(angle, shotPosition, shotSpeed)
    shootingEnabled = false
    wait(for: .random(in: 0.5 * meanShotTime ... 1.5 * meanShotTime)) { self.shootingEnabled = true }
  }

  func warpOut() -> [SKNode] {
    let effect = SKSpriteNode(texture: ufoTexture)
    effect.position = position
    effect.zRotation = zRotation
    effect.shader = warpOutShader
    setStartTimeAttrib(effect)
    let star = starBlink(at: position, throughAngle: -.pi, duration: 2 * warpTime)
    removeFromParent()
    engineSounds.removeFromParent()
    return [effect, star]
  }
  
  func aimAt(_ object: SKNode, shotSpeed s: CGFloat) -> CGFloat? {
    guard let body = object.physicsBody else { return nil }
    let p = object.position - position
    guard let time = aim(at: p, targetVelocity: body.velocity, shotSpeed: s) else { return nil }
    let futurePos = p + body.velocity.scale(by: time)
    return futurePos.angle()
  }
  
  func explode() -> [SKNode] {
    let velocity = physicsBody!.velocity
    engineSounds.removeFromParent()
    removeFromParent()
    return makeExplosion(texture: ufoTexture, angle: zRotation, velocity: velocity, at: position, duration: 2)
  }

  var size: CGSize { return ufoTexture.size() }
}
