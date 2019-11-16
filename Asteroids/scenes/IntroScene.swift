//
//  IntroScene.swift
//  Asteroids
//
//  Created by David Long on 9/22/19.
//  Copyright © 2019 David Long. All rights reserved.
//

import SpriteKit
import AVFoundation

class IntroScene: BasicScene {
  let attributes = AttrStyles(fontName: AppColors.font, fontSize: 40)
  let standBy = """
  Incoming transmission...
  Please stand by.
  """
  let messageHeader = """
  From: @Lt Cmdr Ivanova@
    Sector Head
  To: All @new recruits@
  CC: Central Command
  Subject: @Intro Briefing@
  """
  let introduction = """
  It's tough working in the belt. Whether you're from Luna City, Mars Colony, \
  or good old Terra, out here you're a @long way@ from home. Cleaning the fields \
  from mining debris is a @dangerous@ job; the pay's good for a reason... \
  You're here because you're a @hotshot@ pilot, and Central suspects \
  you @MIGHT@ survive. At least if the pesky @UFOs@ don't get you... Do you \
  have what it takes to become one of us, the @Rock Rats@?
  """
  var incomingLabel: SKLabelNode!
  var introLabel: SKLabelNode!
  var goButton: Button!
  var transmissionSounds: ContinuousPositionalAudio!

  func initIntro() {
    let intro = SKNode()
    intro.name = "intro"
    intro.setZ(.info)
    addChild(intro)
    // It seems that numberOfLines needs to be set to something just to do the word
    // breaking on SKLabelNodes.  The value doesn't really matter though, and we'll
    // adjust the position of the node after computing sizes.
    incomingLabel = SKLabelNode(attributedText: makeAttributed(text: standBy, until: standBy.startIndex, attributes: attributes))
    incomingLabel.numberOfLines = 5
    incomingLabel.lineBreakMode = .byWordWrapping
    incomingLabel.preferredMaxLayoutWidth = 600
    incomingLabel.horizontalAlignmentMode = .center
    incomingLabel.verticalAlignmentMode = .center
    incomingLabel.position = CGPoint(x: gameFrame.midX, y: 0)
    intro.addChild(incomingLabel)
    //incomingLabel.isHidden = true
    introLabel = SKLabelNode(attributedText: makeAttributed(text: introduction, until: introduction.startIndex, attributes: attributes))
    introLabel.numberOfLines = 2
    introLabel.lineBreakMode = .byWordWrapping
    introLabel.preferredMaxLayoutWidth = 900
    introLabel.horizontalAlignmentMode = .center
    introLabel.verticalAlignmentMode = .center
    introLabel.position = CGPoint(x: gameFrame.midX, y: 0)
    intro.addChild(introLabel)
    introLabel.isHidden = true
    goButton = Button(forText: "Find Out", fontSize: 50, size: CGSize(width: 350, height: 50))
    goButton.position = CGPoint(x: fullFrame.midX, y: 0)
    goButton.action = { [unowned self] in self.toMenu() }
    intro.addChild(goButton)
    goButton.alpha = 0
    goButton.isHidden = true
    // Calculate vertical positions for layout
    let introFrame = introLabel.frame
    let spacerHeight = 1.25 * introLabel.fontSize
    let goFrame = goButton.calculateAccumulatedFrame()
    let totalHeight = introFrame.height + spacerHeight + goFrame.height
    let desiredTopY = gameFrame.maxY - 0.5 * (gameFrame.height - totalHeight)
    let desiredBottomY = gameFrame.minY + 0.5 * (gameFrame.height - totalHeight)
    // Put the top of the intro at desiredTopY
    introLabel.position = introLabel.position + CGVector(dx: 0, dy: desiredTopY - introFrame.maxY)
    // Put the bottom of the button at desiredBottomY
    goButton.position = goButton.position + CGVector(dx: 0, dy: desiredBottomY - goFrame.minY)
    transmissionSounds = audio.continuousAudio(.transmission, at: self)
    transmissionSounds.playerNode.volume = 0
    transmissionSounds.playerNode.play()
  }

  func incoming() {
    incomingLabel.typeIn(text: standBy, attributes: attributes, sounds: transmissionSounds) {
      self.wait(for: 3) { self.header() }
    }
  }

  func header() {
    incomingLabel.typeIn(text: messageHeader, attributes: attributes, sounds: transmissionSounds) {
      self.wait(for: 5) {
        self.incomingLabel.isHidden = true
        self.intro()
      }
    }
  }

  func intro() {
    introLabel.isHidden = false
    introLabel.typeIn(text: introduction, attributes: attributes, sounds: transmissionSounds) {
      self.goButton.run(SKAction.sequence([SKAction.unhide(), SKAction.fadeIn(withDuration: 0.5)]))
    }
  }

  func toMenu() {
    wait(for: 0.25) {
      userDefaults.hasDoneIntro.value = true
      self.switchScene(to: Globals.menuScene, withDuration: 3)
    }
    // let tutorialScene = TutorialScene(size: fullFrame.size)
    // wait(for: 0.25) { self.switchScene(to: tutorialScene, withDuration: 3) }
  }

  override func didMove(to view: SKView) {
    super.didMove(to: view)
    wait(for: 1) {
      self.incoming()
    }
    logging("\(name!) finished didMove to view")
  }

  override func update(_ currentTime: TimeInterval) {
    super.update(currentTime)
  }

  override init(size: CGSize) {
    super.init(size: size)
    name = "introScene"
    initGameArea(avoidSafeArea: false)
    initIntro()
  }

  required init(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }
}