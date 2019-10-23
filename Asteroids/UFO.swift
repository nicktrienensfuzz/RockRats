//
//  UFO.swift
//  Asteroids
//
//  Created by Daniel on 8/22/19.
//  Copyright © 2019 David Long. All rights reserved.
//

import SpriteKit
import AVFoundation

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

func wrappedDisplacement(direct: CGVector, bounds: CGRect) -> CGVector {
  let dx1 = direct.dx
  let dx2 = copysign(bounds.width, -dx1) + dx1
  let dx = (abs(dx1) < abs(dx2) ? dx1 : dx2)
  let dy1 = direct.dy
  let dy2 = copysign(bounds.height, -dy1) + dy1
  let dy = (abs(dy1) < abs(dy2) ? dy1 : dy2)
  // The + 5 is because of possible wrapping hysteresis
  assert(abs(dx) <= bounds.width / 2 + 5 && abs(dy) <= bounds.height / 2 + 5)
  return CGVector(dx: dx, dy: dy)
}

class UFO: SKNode {
  let isBig: Bool
  let isKamikaze: Bool
  let ufoTexture: SKTexture
  var currentSpeed: CGFloat
  var engineSounds: ContinuousPositionalAudio? = nil
  let meanShotTime: Double
  var delayOfFirstShot: Double
  var attackEnabled = false
  var shotAccuracy: CGFloat
  var kamikazeAcceleration: CGFloat
  let warpTime = 0.5
  let warpOutShader: SKShader

  required init(brothersKilled: Int, audio: SceneAudio?) {
    let typeChoice = Double.random(in: 0...1)
    let chances = Globals.gameConfig.value(for: \.ufoChances)
    isBig = typeChoice <= chances[0] + chances[1]
    isKamikaze = isBig && typeChoice > chances[0]
    ufoTexture = Globals.textureCache.findTexture(imageNamed: isBig ? (isKamikaze ? "ufo_blue" : "ufo_green") : "ufo_red")
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
    kamikazeAcceleration = Globals.gameConfig.value(for: \.kamikazeAcceleration) * pow(1.25, CGFloat(revengeFactor))
    warpOutShader = fanFoldShader(forTexture: ufoTexture, warpTime: warpTime)
    super.init()
    name = "ufo"
    let ufo = SKSpriteNode(texture: ufoTexture)
    ufo.name = "ufoImage"
    addChild(ufo)
    if let audio = audio {
      let engineSounds = audio.continuousAudio(isBig ? (isKamikaze ? .ufoEnginesMed : .ufoEnginesBig) : .ufoEnginesSmall, at: self)
      engineSounds.playerNode.volume = 0.5
      engineSounds.playerNode.play()
      self.engineSounds = engineSounds
    }
    let body = SKPhysicsBody(circleOfRadius: 0.5 * ufoTexture.size().width)
    body.mass = isBig ? 1 : 0.75
    body.categoryBitMask = ObjectCategories.ufo.rawValue
    body.collisionBitMask = 0
    body.contactTestBitMask = setOf([.asteroid, .ufo, .player, .playerShot])
    body.linearDamping = 0
    body.angularDamping = 0
    body.restitution = 0.9
    body.isOnScreen = false
    // Don't move initially; GameScene will launch us after positioning us at an appropriate spot.
    body.isDynamic = false
    body.angularVelocity = .pi * 2
    physicsBody = body
  }
  
  required init(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented by UFO")
  }

  func fly(player: Ship?, playfield: Playfield, addLaser: ((CGFloat, CGPoint, CGFloat) -> Void)) {
    guard parent != nil else { return }
    let bounds = playfield.bounds
    let body = requiredPhysicsBody()
    guard body.isOnScreen else { return }
    if delayOfFirstShot >= 0 {
      // Just moved onto the screen, enable shooting after a delay.
      // Kamikazes never shoot, but we use the same mechanism to turn off
      // their homing behavior initially.
      wait(for: delayOfFirstShot) { [unowned self] in self.attackEnabled = true }
      delayOfFirstShot = -1
    }
    let maxSpeed = Globals.gameConfig.value(for: \.ufoMaxSpeed)[isBig ? 0 : 1]
    if Int.random(in: 0...100) == 0 {
      if !isKamikaze {
        currentSpeed = .random(in: 0.3 * maxSpeed ... maxSpeed)
      }
      body.angularVelocity = copysign(.pi * 2, -body.angularVelocity)
    }
    let ourRadius = 0.5 * size.diagonal()
    let forceScale = Globals.gameConfig.value(for: \.ufoDodging) * 1000
    let shotAnticipation = Globals.gameConfig.value(for: \.ufoShotAnticipation)
    var totalForce = CGVector.zero
    let interesting = (shotAnticipation > 0 ?
      setOf([.asteroid, .ufo, .player, .playerShot]) :
      setOf([.asteroid, .ufo, .player]))
    // By default, shoot at the player.  If there's an asteroid that's notably closer
    // though, shoot that instead.  In addition to the revenge factor increase in UFO
    // danger, that helps ensure that the player can't sit around and farm UFOs for
    // points forever.
    var potentialTarget: SKNode? = (player?.parent != nil ? player : nil)
    var targetDistance = CGFloat.infinity
    var playerDistance = CGFloat.infinity
    let interestingDistance = 0.33 * min(bounds.width, bounds.height)
    for node in playfield.children {
      // Be sure not to consider off-screen things.  That happens if the last asteroid is
      // destroyed while the UFO is flying around and a new wave spawns.
      guard let body = node.physicsBody, body.isOnScreen else { continue }
      if body.isOneOf(interesting) {
        var r = wrappedDisplacement(direct: node.position - position, bounds: bounds)
        if body.isA(.playerShot) {
          // Shots travel fast, so emphasize dodging to the side.  We do this by projecting out
          // some of the displacement along the direction of the shot.
          let vhat = body.velocity.scale(by: 1 / body.velocity.norm2())
          r = r - r.project(unitVector: vhat).scale(by: shotAnticipation)
        }
        var d = r.norm2()
        if isKamikaze && body.isA(.player) {
          // Kamikazes are alway attracted to the player no matter where they are, but we'll
          // give an initial delay using the same first-shot mechanism before this kicks in.
          if attackEnabled {
            totalForce = totalForce + r.scale(by: kamikazeAcceleration * 1000 / d)
          }
          continue
        }
        // Ignore stuff that's too far away
        guard d <= interestingDistance else { continue }
        var objectRadius = CGFloat(0)
        if body.isA(.asteroid) {
          objectRadius = 0.5 * (node as! SKSpriteNode).size.diagonal()
        } else if body.isA(.ufo) {
          objectRadius = 0.5 * (node as! UFO).size.diagonal()
        } else if body.isA(.player) {
          objectRadius = 0.5 * (node as! Ship).size.diagonal()
          playerDistance = d
        }
        if d < targetDistance && !body.isA(.ufo) {
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
    // Regular UFOs have a desired cruising speed
    if !isKamikaze {
      if body.velocity.norm2() > currentSpeed {
        body.velocity = body.velocity.scale(by: 0.95)
      }
      else if body.velocity.norm2() < currentSpeed {
        body.velocity = body.velocity.scale(by: 1.05)
      }
    }
    if body.velocity.norm2() > maxSpeed {
      body.velocity = body.velocity.scale(by: maxSpeed / body.velocity.norm2())
    }
    guard !isKamikaze else { return }
    if playerDistance < 1.5 * targetDistance || (player?.parent != nil && Int.random(in: 0..<100) >= 25) {
      // Override closest-object targetting if the player is about at the same
      // distance.  Also bias towards randomly shooting at the player even if they're
      // pretty far.
      potentialTarget = player
    }
    guard let target = potentialTarget, attackEnabled else { return }
    let shotSpeed = Globals.gameConfig.value(for: \.ufoShotSpeed)[isBig ? 0 : 1]
    let useBounds = Globals.gameConfig.value(for: \.ufoShotWrapping)
    guard var angle = aimAt(target, shotSpeed: shotSpeed, bounds: useBounds ? bounds : nil) else { return }
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
    attackEnabled = false
    wait(for: .random(in: 0.5 * meanShotTime ... 1.5 * meanShotTime)) { [unowned self] in self.attackEnabled = true }
  }

  func cleanup() {
    engineSounds?.playerNode.stop()
    removeAllActions()
    removeFromParent()
  }

  func warpOut() -> [SKNode] {
    let effect = SKSpriteNode(texture: ufoTexture)
    effect.position = position
    effect.zRotation = zRotation
    effect.shader = warpOutShader
    setStartTimeAttrib(effect, view: scene?.view)
    effect.run(SKAction.sequence([SKAction.wait(forDuration: warpTime), SKAction.removeFromParent()]))
    let star = starBlink(at: position, throughAngle: -.pi, duration: 2 * warpTime)
    cleanup()
    return [effect, star]
  }
  
  func aimAt(_ object: SKNode, shotSpeed s: CGFloat, bounds: CGRect?) -> CGFloat? {
    guard let body = object.physicsBody else { return nil }
    var p = object.position - position
    if let bounds = bounds {
      p = wrappedDisplacement(direct: p, bounds: bounds)
    }
    guard let time = aim(at: p, targetVelocity: body.velocity, shotSpeed: s) else { return nil }
    let futurePos = p + body.velocity.scale(by: time)
    return futurePos.angle()
  }
  
  func explode() -> [SKNode] {
    let velocity = physicsBody!.velocity
    cleanup()
    return makeExplosion(texture: ufoTexture, angle: zRotation, velocity: velocity, at: position, duration: 2)
  }

  var size: CGSize { return ufoTexture.size() }
}
