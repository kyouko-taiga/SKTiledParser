//
//  SKTiledParser
//  SKTiledParser.swift
//
//  Created by Dimitri Racordon on 17.11.16.
//
//

import SpriteKit
import GameKit


// MARK: SKTiledLayout

open class SKTiledLayout {

    // MARK: Properties

    open let baseLayer: SKTileMapNode
    open let tilesLayers: [SKTileMapNode]
    open let orientation: SKTileSetType

    open lazy var numberOfColumns: Int = {
        return self.baseLayer.numberOfColumns
    }()

    open lazy var numberOfRows: Int = {
        return self.baseLayer.numberOfRows
    }()

    // MARK: Functions

    public init(
        baseLayer: SKTileMapNode, tilesLayers: [SKTileMapNode],
        orientation: SKTileSetType) {

        self.baseLayer = baseLayer
        self.tilesLayers = tilesLayers
        self.orientation = orientation

        for tilesLayer in tilesLayers {
            baseLayer.addChild(tilesLayer)
        }
    }

    public convenience init?(tilesLayers: [SKTileMapNode]) {
        // Fail to initialize if there isn't at least 1 layer.
        guard tilesLayers.count >= 1 else {
            return nil
        }

        // Determine the dimension and orientation of the the base layer.
        var columns = 0
        var rows = 0
        var orientation: SKTileSetType?
        var tileSize: CGSize?

        for layer in tilesLayers {
            columns = max(columns, layer.numberOfColumns)
            rows = max(rows, layer.numberOfColumns)

            if orientation == nil {
                orientation = layer.tileSet.type
            }

            if tileSize == nil {
                tileSize = layer.tileSize
            }
        }

        self.init(
            baseLayer: SKTileMapNode(
                tileSet: SKTileSet(tileGroups: [], tileSetType: orientation!),
                columns: columns,
                rows: rows,
                tileSize: tileSize!),
            tilesLayers: tilesLayers,
            orientation: orientation!)
    }

    open func computePathfindingGraph<NodeClass>(
        usingLayers layers: [SKTileMapNode]) -> GKGridGraph<NodeClass> {

        let graph = GKGridGraph(
            fromGridStartingAt: vector_int2(0, 0),
            width: Int32(self.numberOfColumns),
            height: Int32(self.numberOfRows),
            diagonalsAllowed: false,
            nodeClass: NodeClass.self)

        var obstacles = [GKGraphNode]()

        for layer in layers {
            for col in 0 ..< self.numberOfColumns {
                for row in 0 ..< self.numberOfRows {
                    // Remove node at <col, row> from the graph if a tile was placed at the same
                    // coordinates.
                    if layer.tileDefinition(atColumn: col, row: row) != nil {
                        obstacles.append(
                            graph.node(atGridPosition: vector_int2(Int32(col), Int32(row)))!)
                    }
                }
            }
        }

        graph.remove(obstacles)
        return graph as! GKGridGraph<NodeClass>
    }

    open func computePathfindingGraph<NodeClass>(
        usingLayersNamed names: [String]) -> GKGridGraph<NodeClass> {

        let collisionLayers = self.tilesLayers.filter {
            ($0.name != nil) && (names.contains($0.name!))
        }

        return self.computePathfindingGraph(usingLayers: collisionLayers)
    }

}


// MARK: SKTiledParser

public class SKTiledParser : NSObject, XMLParserDelegate {

    // MARK: Properties

    public let texturesNamespace: String

    private var errorMessage = ""

    private var columns = 0
    private var rows = 0
    private var tileSize = CGSize.zero
    private var orientation: SKTileSetType = .isometric

    private var baseTileMap: SKTileMapNode?
    private var tileMaps = [SKTileMapNode]()
    private var objectGroups = [SKNode]()

    private var tileGroups = [Int: (SKTileGroup, SKTileSet)]()
    private var textures = [Int: SKTexture]()

    private var currentTileSet: SKTileSet?
    private var currentStartingId: Int?
    private var currentTileAttributes: TileAttributes?

    private var currentLayerAttributes: LayerAttributes?
    private var currentTileMap: SKTileMapNode?
    private var currentPosition: (x: Int, y: Int) = (0, 0)

    private var currentObjectGroup: SKNode?

    // MARK: Functions

    public init(texturesNamespace: String = "") {
        self.texturesNamespace = texturesNamespace
    }

    /// Creates an SKTiledLayout from a .tmx tilemap file.
    public func loadLayout(fromFileNamed filename: String) -> SKTiledLayout? {

        guard let url = Bundle.main.url(forResource: filename, withExtension: ".tmx") else {
            print("SKTiledParser: (error) tilemap '\(filename)' couldn't be found")
            return nil
        }

        let data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch let error {
            self.log(error.localizedDescription, level: "error")
            return nil
        }

        let parser = XMLParser(data: data!)
        parser.delegate = self
        self.errorMessage = "couldn't parse \(filename)"

        if parser.parse() {
            let layout = SKTiledLayout(
                baseLayer: self.baseTileMap!,
                tilesLayers: self.tileMaps,
                orientation: self.orientation)

            for objectGroup in self.objectGroups {
                layout.baseLayer.addChild(objectGroup)
            }

            return layout
        }

        self.log(self.errorMessage, level: "error")
        return nil
    }

    func log(_ message: String, level: String = "warning") {
        print("SKTiledParser: (\(level)) \(message)")
    }

    // MARK: NSXMLParser Delegate Functions

    public func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {

        switch elementName {
        case "map":
            guard
                let columns = self.readInt("width", from: attributeDict),
                let rows = self.readInt("height", from: attributeDict) else {
                    self.errorMessage = "missing or invalid map size, line \(parser.lineNumber)"
                    parser.abortParsing()
                    return
            }

            self.columns = columns
            self.rows = rows
            self.currentPosition.y = self.rows - 1

            guard
                let tileWidth = self.readInt("tilewidth", from: attributeDict),
                let tileHeight = self.readInt("tileheight", from: attributeDict) else {
                    self.errorMessage = "missing or invalid tile size, line \(parser.lineNumber)"
                    parser.abortParsing()
                    return
            }

            self.tileSize = CGSize(width: tileWidth, height: tileHeight)

            if let orientation = attributeDict["orientation"] {
                if orientation == "isometric" {
                    self.orientation = .isometric
                } else if orientation == "orthogonal" {
                    self.orientation = .grid
                } else if orientation == "hexagonal" {
                    self.orientation = .hexagonalFlat
                } else {
                    self.log(
                        "unsupported orientation '\(orientation)', will use .grid instead, " +
                        "line \(parser.lineNumber)")
                    self.orientation = .grid
                }
            }

            self.baseTileMap = SKTileMapNode(
                tileSet: SKTileSet(tileGroups: [], tileSetType: orientation),
                columns: self.columns,
                rows: self.rows,
                tileSize: self.tileSize)

        case "tileset":
            guard let firstgid = self.readInt("firstgid", from: attributeDict) else {
                self.log(
                    "missing or invalid property 'firstgid' on tileset element, tileset will be " +
                    "ignored, line \(parser.lineNumber)")
                return
            }

            // Update the state of the parser so that we can parse all tile definitions.
            self.currentTileSet = SKTileSet()
            self.currentTileSet?.type = self.orientation
            self.currentTileSet?.name = attributeDict["name"]
            self.currentStartingId = firstgid

        case "tile":
            if self.currentTileSet != nil {
                // If the current tileset isn't nil, we're about to parse the tile definitions of
                // a tileset.
                guard let id = self.readInt("id", from: attributeDict) else {
                    self.log(
                        "missing or invalid property 'id' on tile element, tile definition will " +
                        "be ignored, line \(parser.lineNumber)")
                    return
                }

                // Update the state of the parser so that we can parse the current tile definition.
                self.currentTileAttributes = TileAttributes()
                self.currentTileAttributes!.id = currentStartingId! + id
            } else {
                // Otherwise, we're parsing the a layer definition.
                defer {
                    // Compute the position of the next tile to place.
                    if self.currentPosition.x == self.columns - 1 {
                        self.currentPosition.x = 0
                        self.currentPosition.y -= 1
                    } else {
                        self.currentPosition.x += 1
                    }
                }

                guard let gid = self.readInt("gid", from: attributeDict) else {
                    self.log(
                        "missing or invalid property 'gid' on tile element, tile at position " +
                        "\(self.currentPosition.x), \(self.currentPosition.y) won't be, " +
                        "placed, line \(parser.lineNumber)")
                    return
                }

                // If the parsed gid is 0, there's no tile to place.
                if gid == 0 {
                    return
                }

                guard let (tileGroup, tileSet) = self.tileGroups[gid] else {
                    self.log(
                        "unassigned tile gid, tile at position " +
                        "\(self.currentPosition.x), \(self.currentPosition.y) won't be, " +
                        "placed, line \(parser.lineNumber)")
                    return
                }

                // Create a new tilemap if we're placing the first tile.
                if self.currentTileMap == nil {
                    self.currentTileMap = SKTileMapNode(
                        tileSet: tileSet,
                        columns: self.columns,
                        rows: self.rows,
                        tileSize: self.tileSize)

                    // Set the name of the tilemap node if we could parse it.
                    self.currentTileMap!.name = self.currentLayerAttributes?.name

                    // Apply the layer offset (if we could parse it) on the tilemap position.
                    if let offsetX = self.currentLayerAttributes?.offsetX {
                        self.currentTileMap!.position.x = CGFloat(offsetX)
                    }
                    if let offsetY = self.currentLayerAttributes?.offsetY {
                        self.currentTileMap!.position.y = CGFloat(offsetY)
                    }
                }

                // Make sure the tileset of the current tilemap matches that of the given tile
                // definition.
                if self.currentTileMap!.tileSet != tileSet {
                    self.errorMessage =
                        "all tiles of a tilemap should come from the same tileset, " +
                        "line \(parser.lineNumber)"
                    parser.abortParsing()
                }

                // Place the tile.
                self.currentTileMap!.setTileGroup(
                    tileGroup, forColumn: self.currentPosition.x, row: self.currentPosition.y)
            }

        case "image":
            // Get the name of the texture associated with the current tile.
            guard
                let source = attributeDict["source"],
                let textureName = (source as NSString).lastPathComponent.components(
                    separatedBy: ".").first else {
                        self.log(
                            "missing or invalid property 'source' on image element, texture " +
                            "will be ignored, line \(parser.lineNumber)")
                        return
            }

            self.currentTileAttributes?.texture = SKTexture(
                imageNamed: self.texturesNamespace + textureName)

        case "property":
            guard
                let name = attributeDict["name"],
                let value = attributeDict["value"] else {
                    self.log(
                        "custom property will be ignored because it couldn't be parsed, " +
                        "line \(parser.lineNumber)")
                    return
            }

            if var tileAttributes = self.currentTileAttributes {
                let propertyType = attributeDict["type"] ?? "string"
                switch propertyType {
                case "int":
                    tileAttributes.userData[name] = Int(value)
                case "float":
                    tileAttributes.userData[name] = Float(value)
                case "bool":
                    tileAttributes.userData[name] = (value == "true")
                default:
                    tileAttributes.userData[name] = value
                }
            } else {
                // TODO: Handle custom properties on maps, layers, objectgroups and objects.
                self.log("custom property will be ignored, line \(parser.lineNumber)")
            }

        case "layer":
            self.currentLayerAttributes = LayerAttributes()
            currentLayerAttributes!.name = attributeDict["name"]

            if let offsetX = self.readInt("offsetx", from: attributeDict) {
                self.currentLayerAttributes!.offsetX = offsetX
            }

            if let offsetY = self.readInt("offsety", from: attributeDict) {
                self.currentLayerAttributes!.offsetY = -offsetY
            }

        case "objectgroup":
            self.currentObjectGroup = SKNode()
            self.currentObjectGroup!.name = attributeDict["name"]

            if let offsetX = self.readInt("offsetx", from: attributeDict) {
                self.currentObjectGroup!.position.x = CGFloat(offsetX)
            }

            if let offsetY = self.readInt("offsety", from: attributeDict) {
                self.currentObjectGroup!.position.y = -CGFloat(offsetY)
            }

        case "object":
            var object: SKNode? = nil

            // If the object has a property "gid", we'll fetch the corresponding texture to create
            // an SKSpriteNode. Otherwise we'll create a generic SKNode.
            if let gid = self.readInt("gid", from: attributeDict) {
                if let width = self.readInt("width", from: attributeDict),
                   let height = self.readInt("height", from:attributeDict) {
                    object = SKSpriteNode(
                        texture: self.textures[gid],
                        size: CGSize(width: width, height: height))
                } else {
                    object = SKSpriteNode(texture: self.textures[gid])
                }

                // Set the vertical position of the anchor point so that the bottom of the sprite
                // touches the bottom of a tile.
                let sprite = object as! SKSpriteNode
                sprite.anchorPoint.y = (self.tileSize.height / 2) / sprite.size.height
            } else {
                object = SKNode()
            }

            object!.name = attributeDict["name"]

            // Parse the object position.
            if let x = self.readInt("x", from: attributeDict),
               let y = self.readInt("y", from: attributeDict) {
                if self.orientation == .isometric {
                    // In isometric tilemaps, Tiled sets object positions according to the
                    // isometric axis rather than the orthogonal ones. As a result, we should
                    // recompute all coordinates in SpriteKit's coordinate system.
                    let col = CGFloat(x) / self.tileSize.height - 1
                    let row = -CGFloat(y) / self.tileSize.height + CGFloat(self.rows)

                    // Check for boundaries.
                    if !(0 ..< self.columns ~= Int(col)) || !(0 ..< self.rows ~= Int(row)) {
                        self.log(
                            "object \(attributeDict["id"]!) is outside the layout boundaries, " +
                            "line \(parser.lineNumber)")
                    }

                    object!.position = self.baseTileMap!.centerOfTile(
                        atColumn: Int(col), row: Int(row))
                }

                // TODO: Handle object position with other orientations.

                self.currentObjectGroup?.addChild(object!)
            } else {
                self.log(
                    "object \(attributeDict["id"]!) will be ignored because its position " +
                    "couldn't be parsed, line \(parser.lineNumber)")
            }

        // TODO: Handle tile offsets and animations.
        case "tileoffset", "animation", "frame":
            self.log("\(elementName) element will be ignored, line \(parser.lineNumber)")

        default:
            break
        }
    }

    public func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?) {

        switch elementName {
        case "tileset":
            // Reset the state of the parser.
            self.currentTileSet = nil
            self.currentStartingId = nil

        case "tile":
            // If the current tile attributes struct isn't nil, we're about to finish parsing a
            // tile definition.
            if let tileAttributes = self.currentTileAttributes {
                defer {
                    // Reset the state of the parser.
                    self.currentTileAttributes = nil
                }

                guard let texture = tileAttributes.texture else {
                    self.log(
                        "undefined texture, tile definition will be skipped " +
                        "line \(parser.lineNumber)")
                    return
                }

                // Create the tile group and add it to the tileset.
                let tileDefinition = SKTileDefinition(texture: texture)
                tileDefinition.userData = NSMutableDictionary(dictionary: tileAttributes.userData)

                let tileGroup = SKTileGroup(tileDefinition: tileDefinition)
                self.currentTileSet!.tileGroups.append(tileGroup)

                self.tileGroups[tileAttributes.id!] = (tileGroup, self.currentTileSet!)
                self.textures[tileAttributes.id!] = texture
            }

        case "layer":
            // Register the parsed tilemap.
            self.tileMaps.append(self.currentTileMap!)

            // Reset the state of the parser.
            self.currentLayerAttributes = nil
            self.currentTileMap = nil
            self.currentPosition = (0, self.rows - 1)

        case "objectgroup":
            // Register the parsed object group.
            self.objectGroups.append(self.currentObjectGroup!)

            // Reset the state of the parser.
            self.currentObjectGroup = nil

        default:
            break
        }
    }

    // MARK: Helper functions
    func readInt(_ attributeName: String, from attributeDict: [String: String]) -> Int? {
        if let value = attributeDict[attributeName] {
            return Int(value)
        }
        return nil
    }

}


// MARK: TileAttributes

fileprivate struct TileAttributes {
    var id: Int?
    var texture: SKTexture?
    var userData = [String: Any]()
}


// MARK: LayerAttributes

fileprivate struct LayerAttributes {
    var name: String?
    var offsetX: Int?
    var offsetY: Int?
}
