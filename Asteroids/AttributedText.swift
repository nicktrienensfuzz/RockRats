//
//  AttributedText.swift
//  Asteroids
//
//  Copyright © 2020 Daniel Long and David Long
//
//  License: MIT
//
//  See LICENSE.md in the top-level directory for full terms and discussion.
//

import SpriteKit

/// Styles use for making attributed text
struct AttrStyles {
  /// The font name being used
  let fontName: String
  /// The font size being used
  let fontSize: CGFloat
  /// Normal text
  let textAttributes: [NSAttributedString.Key: Any]
  /// Highlighted text
  let highlightTextAttributes: [NSAttributedString.Key: Any]
  /// Hiddent text
  let hiddenAttributes: [NSAttributedString.Key: Any]

  init(fontName: String, fontSize: CGFloat) {
    self.fontName = fontName
    self.fontSize = fontSize
    var attributes = [NSAttributedString.Key: Any]()
    attributes[.font] = UIFont(name: fontName, size: fontSize)
    attributes[.foregroundColor] = AppAppearance.textColor
    self.textAttributes = attributes
    attributes[.foregroundColor] = AppAppearance.highlightTextColor
    self.highlightTextAttributes = attributes
    attributes[.foregroundColor] = UIColor.clear
    self.hiddenAttributes = attributes
  }
}

/// Make an attributed string from a simple textual description
///
/// Surround highlighted text with @at signs@ and hidden text with %percent signs%.
///
/// - Parameters:
///   - text: The text
///   - invisibleIndex: Text from this position to the end is automatically invisible
///   - attributes: An `AttrStyles` describing the attributes of the different styles
/// - Returns: The attributed string
func makeAttributed(text: String, until invisibleIndex: String.Index, attributes: AttrStyles) -> NSAttributedString {
  var highlighted = false
  var hidden = false
  let result = NSMutableAttributedString(string: "")
  var index = text.startIndex
  while index < text.endIndex {
    if text[index] == "@" {
      highlighted = !highlighted
    } else if text[index] == "%" {
      hidden = !hidden
    } else {
      if index < invisibleIndex && !hidden {
        if highlighted {
          result.append(NSAttributedString(string: String(text[index]), attributes: attributes.highlightTextAttributes))
        } else {
          result.append(NSAttributedString(string: String(text[index]), attributes: attributes.textAttributes))
        }
      } else {
        result.append(NSAttributedString(string: String(text[index]), attributes: attributes.hiddenAttributes))
      }
    }
    index = text.index(after: index)
  }
  return result
}
