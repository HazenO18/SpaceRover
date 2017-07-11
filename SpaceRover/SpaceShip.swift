//
//  SpaceShip.swift
//  SpaceRover
//
//  Created by Hazen O'Malley on 6/4/17.
//  Copyright © 2017 Hazen O'Malley. All rights reserved.
//

import SpriteKit

struct SlantPoint: Equatable {
  var x: Int
  var y: Int
  
  static func ==(lhs: SlantPoint, rhs: SlantPoint) -> Bool {
    return lhs.x == rhs.x && lhs.y == rhs.y
  }
  
  static func +(lhs: SlantPoint, rhs: SlantPoint) -> SlantPoint {
    return SlantPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
  }
}

enum HexDirection: Int {
  case NoAcc, West, NorthWest, NorthEast, East, SouthEast, SouthWest;
}

extension HexDirection {
  static func all() -> AnySequence<HexDirection> {
    return AnySequence {
      return HexDirectionGenerator()
    }
  }

  struct HexDirectionGenerator: IteratorProtocol {
    var currentSection = 0

    mutating func next() -> HexDirection? {
      guard let item = HexDirection(rawValue:currentSection) else {
        return nil
      }
      currentSection += 1
      return item
    }
  }

  func invert() -> HexDirection {
    switch (self) {
    case .NoAcc:
      return .NoAcc
    case .NorthEast:
      return .SouthWest
    case .NorthWest:
      return .SouthEast
    case .West:
      return .East
    case .East:
      return .West
    case .SouthWest:
      return .NorthEast
    case .SouthEast:
      return .NorthWest
    }
  }

  func clockwise(turns: Int) -> HexDirection {
    if (self == .NoAcc) {
      return .NoAcc
    } else {
      var newValue = ((self.rawValue - 1) + turns) % 6
      if (newValue < 0) {
        newValue += 6
      }
      return HexDirection(rawValue: newValue + 1)!
    }
  }
  
  func rotateAngle() -> Double {
    switch (self) {
    case .NoAcc:
      return 0
    case .NorthEast:
      return 0
    case .East:
      return 5*Double.pi/3
    case .SouthEast:
      return 4*Double.pi/3
    case .SouthWest:
      return 3*Double.pi/3
    case .West:
      return 2*Double.pi/3
    case .NorthWest:
      return 1*Double.pi/3
    }
  }
  
  /**
   * Get the SlantPoint vector going in this direction
   */
  func toSlant() -> SlantPoint {
    switch (self) {
    case .NoAcc:
      return SlantPoint(x: 0, y: 0)
    case .NorthEast:
      return SlantPoint(x: 1, y: 1)
    case .East:
      return SlantPoint(x: 1, y: 0)
    case .SouthEast:
      return SlantPoint(x: 0, y: -1)
    case .SouthWest:
      return SlantPoint(x: -1, y: -1)
    case .West:
      return SlantPoint(x: -1, y: 0)
    case .NorthWest:
      return SlantPoint(x: 0, y: 1)
    }
  }
}

func slantToView(_ pos: SlantPoint, tiles: SKTileMapNode) -> CGPoint {
  return tiles.centerOfTile(atColumn: pos.x - ((pos.y+1) / 2), row: pos.y)
}

/**
 * Compute the relative position in the given direction.
 */
func findRelativePosition(_ direction: HexDirection, tiles: SKTileMapNode) -> CGPoint {
  // pick a point that won't cause the relative points to go out of bounds
  let originSlant = SlantPoint(x: 2, y: 2)
  // get the relative slant point
  let slant = originSlant + direction.toSlant()
  let posn = slantToView(slant, tiles: tiles)
  // subtract off the origin
  let origin = slantToView(originSlant, tiles: tiles)
  return CGPoint(x: posn.x - origin.x, y: posn.y - origin.y)
}

let shipContactMask: UInt32 = 1
let planetContactMask: UInt32 = 2
let gravityContactMask: UInt32 = 4
let accelerationContactMask: UInt32 = 8

protocol ShipInformationWatcher {
  func updateShipInformation(_ msg: String)
}

class SpaceShip: SKSpriteNode {

  let tileMap: SKTileMapNode
  let fuelCapacity = 20
  var arrows : DirectionArrow?

  var slant: SlantPoint
  var velocity: SlantPoint
  var direction = HexDirection.NorthEast
  var fuel: Int
  var watcher: ShipInformationWatcher?
  
  init (name: String, slant: SlantPoint, tiles: SKTileMapNode) {
    tileMap = tiles
    self.slant = slant
    velocity = SlantPoint(x: 0, y: 0)
    let texture = SKTexture(imageNamed: "SpaceshipUpRight")
    fuel = fuelCapacity
    super.init(texture: texture, color: UIColor.clear, size: texture.size())
    self.name = name
    position = slantToView(slant, tiles: tileMap)
    tileMap.addChild(self)
    arrows = DirectionArrow(ship: self)
    arrows!.position = self.position
    tileMap.addChild(arrows!)
    zPosition = 20
    physicsBody = SKPhysicsBody(circleOfRadius: 5)
    physicsBody?.categoryBitMask = shipContactMask
    physicsBody?.contactTestBitMask = planetContactMask | gravityContactMask
    physicsBody?.collisionBitMask = 0
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setWatcher(_ newWatcher: ShipInformationWatcher?) {
    watcher = newWatcher
    watcher?.updateShipInformation(getInformation())
  }
  
  func getAccellerationPosition(direction: HexDirection) -> CGPoint {
    let newVelocity = velocity + direction.toSlant()
    let newPosition = slant + newVelocity
    return slantToView(newPosition, tiles: tileMap)
  }

  func enterGravity(_ gravity: GravityArrow) {
    print("\(self.name!) hit \(gravity.name!)")
    accelerateShip(direction: gravity.direction)
  }

  func accelerateShip(direction: HexDirection) {
    velocity = velocity + direction.toSlant()
    moveAccArrows()
  }

  func inOrbit() -> Planet? {
    for body in physicsBody!.allContactedBodies() {
      if let gravity = body.node as? GravityArrow {
        // Is the velocity 60 degrees from the gravity?
        let clockwise = gravity.direction.clockwise(turns: 1).toSlant()
        let counterClockwise = gravity.direction.clockwise(turns: -1).toSlant()
        if velocity == clockwise || velocity == counterClockwise {
          return gravity.planet
        }
      }
    }
    return nil
  }
  
  func rotateShip (_ newDirection : HexDirection) {
    if newDirection != direction && newDirection != HexDirection.NoAcc {
      var rotateBy = (newDirection.rotateAngle() - direction.rotateAngle())
      if (rotateBy >= 0) {
        while (rotateBy > Double.pi) {
          rotateBy -= 2*Double.pi
        }
      } else {
        while (rotateBy < -Double.pi) {
          rotateBy += 2*Double.pi
        }
      }
      direction = newDirection
      self.run(SKAction.rotate(byAngle: CGFloat(rotateBy), duration: 0.5))
    }
  }

  func getInformation() -> String {
    if let planet = inOrbit() {
      return "\(name!)\nFuel: \(fuel)\n\(planet.name!) orbit"
    } else {
      return "\(name!)\nFuel: \(fuel)"
    }
  }
  
  func useFuel(_ units: Int) {
    fuel -= units
    watcher?.updateShipInformation(getInformation())
    if (fuel == 0) {
      arrows?.outOfFuel()
      //"We're outta rockets sir."
    }
  }
  
  func moveAccArrows(){
    arrows?.removeAllActions()
    arrows?.run(
        SKAction.move(to: getAccellerationPosition(direction: HexDirection.NoAcc), duration: 1))
  }
  
  func move() {
    print("moving \(name!) by \(velocity)")
    if (velocity.x == 0 && velocity.y == 0){
      if let list = physicsBody?.allContactedBodies() {
        for body in list {
          if let node = body.node as? GravityArrow {
            accelerateShip(direction: node.direction)
          }
        }
      }
    } else {
      slant.x += velocity.x
      slant.y += velocity.y
      run(SKAction.move(to: slantToView(slant, tiles: tileMap), duration: 1))
      self.moveAccArrows()
      //vroom vroom
    }
  }
}

class Planet: SKSpriteNode {

  convenience init(name: String, slant: SlantPoint, tiles: SKTileMapNode) {
    self.init(name:name, image:name, slant:slant, tiles:tiles)
  }
  
  init(name: String, image: String, slant: SlantPoint, tiles: SKTileMapNode) {
    let texture = SKTexture(imageNamed: image)
    super.init(texture: texture, color: UIColor.clear, size: (texture.size()))
    let nameLabel = SKLabelNode(text: name)
    nameLabel.zPosition = 1
    nameLabel.position = CGPoint(x: 0, y: 25)
    nameLabel.fontSize = 20
    nameLabel.fontName = "Copperplate"
    addChild(nameLabel)
    self.name = name
    position = slantToView(slant, tiles: tiles)
    zPosition = 10
    for direction in HexDirection.all() {
      if direction != HexDirection.NoAcc {
        let posn = findRelativePosition(direction.invert(), tiles: tiles)
        addChild(GravityArrow(direction: direction, planet: self, position: posn))
      }
    }
    physicsBody = SKPhysicsBody(circleOfRadius: 50)
    physicsBody?.categoryBitMask = planetContactMask
    physicsBody?.contactTestBitMask = shipContactMask | accelerationContactMask
    physicsBody?.collisionBitMask = 0
    physicsBody?.isDynamic = false
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

class GravityArrow: SKSpriteNode {
  let direction: HexDirection
  let planet: Planet

  init(direction: HexDirection, planet: Planet, position: CGPoint) {
    self.direction = direction
    self.planet = planet
    let texture = SKTexture(imageNamed: "GravityArrow")
    // Create the hexagon with the additional wedge toward the planet
    let bodyShape = CGMutablePath()
    bodyShape.addLines(between: [CGPoint(x:111, y:0),
                                 CGPoint(x:0, y:-64),
                                 CGPoint(x:-55, y:-32),
                                 CGPoint(x:-55, y:32),
                                 CGPoint(x:0, y:64),
                                 CGPoint(x:111, y:0)])
    super.init(texture: texture, color: UIColor.clear, size: (texture.size()))
    self.name = "Gravity \(direction) toward \(planet.name!)"
    zPosition = 10
    alpha = 0.6
    self.position = position
    physicsBody = SKPhysicsBody(polygonFrom: bodyShape)
    physicsBody?.categoryBitMask = gravityContactMask
    physicsBody?.contactTestBitMask = shipContactMask
    physicsBody?.collisionBitMask = 0
    physicsBody?.isDynamic = false
    let sixtyDegree = Double.pi / 3
    run(SKAction.rotate(byAngle: CGFloat(sixtyDegree + direction.rotateAngle()), duration: 0))
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/**
 * The arrows that let the user pick the direction.
 */
class DirectionArrow: SKSpriteNode{
  let direction: HexDirection
  let ship: SpaceShip
  
  /**
   * Constructor for the parent arrow
   */
  init(ship: SpaceShip) {
    self.ship = ship
    self.direction = HexDirection.NoAcc
    let texture = SKTexture(imageNamed: "NoAccelerationSymbol")
    super.init(texture: texture, color: UIColor.clear, size: (texture.size()))
    name = "\(direction) arrow for \(ship.name!)"
    alpha = 1
    zPosition = 50
    isUserInteractionEnabled = true
    physicsBody = createPhysics()
    for childDir in HexDirection.all() {
      if (childDir != HexDirection.NoAcc) {
        addChild(DirectionArrow(ship: ship, direction: childDir))
      }
    }
  }
  
  /**
   * Constructor for the children arrows
   */
  init(ship: SpaceShip, direction: HexDirection) {
    self.ship = ship
    self.direction = direction

    let texture = SKTexture(imageNamed: "MovementArrow")
    super.init(texture: texture, color: UIColor.clear, size: (texture.size()))
    name = "\(direction) arrow for \(ship.name!)"
    alpha = 0.8

    self.run(SKAction.rotate(toAngle: CGFloat(direction.rotateAngle()), duration: 0))
    isUserInteractionEnabled = true
    position = findRelativePosition(direction, tiles: ship.tileMap)
    physicsBody = createPhysics()
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func createPhysics() -> SKPhysicsBody {
    let newPhysicsBody = SKPhysicsBody(circleOfRadius: 10)
    newPhysicsBody.categoryBitMask = accelerationContactMask
    newPhysicsBody.contactTestBitMask = planetContactMask
    newPhysicsBody.collisionBitMask = 0
    newPhysicsBody.isDynamic = true
    return newPhysicsBody
  }
  
  func outOfFuel() {
    for child in children {
      child.isHidden = true
    }
  }
  
  func refuelled() {
    for child in children {
      child.isHidden = false
    }
  }
  
  func overPlanet(_ planet: Planet) {
    print("\(self.name!) overlapping \(planet.name!)")
  }
  
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    /* Called when a touch begins */
    for _ in touches {
      if (direction != HexDirection.NoAcc) {
        ship.accelerateShip(direction: direction)
        ship.useFuel(1)
        ship.rotateShip(direction)
      }
      ship.move()
    }
  }
}
