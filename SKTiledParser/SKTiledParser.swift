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

class SKTiledLayout {

    // MARK: Properties

    let rootNode: SKNode

    let width: Int
    let height: Int

    let layers: [SKTileMapNode]
    let tileSets: [SKTileSet]
    let orientation: SKTileSetType

    // MARK: Functions

    init(
        width: Int, height: Int, layers: [SKTileMapNode], tileSets: [SKTileSet],
        orientation: SKTileSetType) {

        self.width = width
        self.height = height

        self.layers = layers
        self.tileSets = tileSets
        self.orientation = orientation

        self.rootNode = SKNode()

        for layer in layers {
            rootNode.addChild(layer)
        }
    }

    func computePathfindingGraph<NodeClass>(
        usingLayers layers: [SKTileMapNode]) -> GKGridGraph<NodeClass> {

        let graph = GKGridGraph(
            fromGridStartingAt: vector_int2(0, 0),
            width: Int32(self.width),
            height: Int32(self.height),
            diagonalsAllowed: false,
            nodeClass: NodeClass.self)

        var obstacles = [GKGraphNode]()

        for layer in layers {
            for col in 0 ..< self.width {
                for row in 0 ..< self.height {
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

    func computePathfindingGraph<NodeClass>(
        usingLayersNamed names: [String]) -> GKGridGraph<NodeClass> {

        return self.computePathfindingGraph(
            usingLayers: self.layers.filter { ($0.name != nil) && (names.contains($0.name!)) })
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


// MARK: SKTiledParser

class SKTiledParser : NSObject, XMLParserDelegate {

    // MARK: Properties

    public let texturesNamespace: String

    private var errorMessage = ""

    private var width = 0
    private var height = 0
    private var tileSize = CGSize.zero
    private var orientation: SKTileSetType = .isometric

    private var tileMaps = [SKTileMapNode]()
    private var tileSets = [SKTileSet]()

    private var tileGroups = [Int: (SKTileGroup, SKTileSet)]()

    private var currentTileSet: SKTileSet?
    private var currentStartingId: Int?
    private var currentTileAttributes: TileAttributes?

    private var currentLayerAttributes: LayerAttributes?
    private var currentTileMap: SKTileMapNode?
    private var currentPosition: (x: Int, y: Int) = (0, 0)

    // MARK: Functions

    init(texturesNamespace: String = "") {
        self.texturesNamespace = texturesNamespace
    }

    /// Creates an SKTiledLayout from a .tmx tilemap file.
    func loadLayout(fromFileNamed filename: String) -> SKTiledLayout? {

        guard let url = Bundle.main.url(forResource: filename, withExtension: ".tmx") else {
            print("SKTiledParser: (error) tilemap '\(filename)' couldn't be found")
            return nil
        }

        let data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch let error {
            print("SKTiledParser: \(error.localizedDescription)")
            return nil
        }

        let parser = XMLParser(data: data!)
        parser.delegate = self
        self.errorMessage = "couldn't parse \(filename)"

        if parser.parse() {
            return SKTiledLayout(
                width: self.width,
                height: self.height,
                layers: self.tileMaps,
                tileSets: self.tileSets,
                orientation: self.orientation)
        }

        print("SKTiledParser: (error) " + self.errorMessage)
        return nil
    }

    // MARK: NSXMLParser Delegate Functions

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {

        switch elementName {
        case "map":
            guard
                let width = attributeDict["width"],
                let height = attributeDict["height"] else {
                    self.errorMessage = "missing map dimensions [\(parser.lineNumber)]"
                    parser.abortParsing()
                    return
            }

            self.width = Int(width)!
            self.height = Int(height)!
            self.currentPosition.y = self.height - 1

            guard
                let tileWidth = attributeDict["tilewidth"],
                let tileHeight = attributeDict["tileheight"] else {
                    self.errorMessage = "missing tile dimensions [\(parser.lineNumber)]"
                    parser.abortParsing()
                    return
            }

            self.tileSize = CGSize(width: Int(tileWidth)!, height: Int(tileHeight)!)

            if let orientation = attributeDict["orientation"] {
                if orientation == "isometric" {
                    self.orientation = .isometric
                } else if orientation == "orthogonal" {
                    self.orientation = .grid
                } else if orientation == "hexagonal" {
                    self.orientation = .hexagonalFlat
                } else {
                    print(
                        "SKTiledParser: (warning) unsupported orientation '\(orientation)', " +
                        "defined at [\(parser.lineNumber)]; will use .grid instead")
                    self.orientation = .grid
                }
            }

        case "tileset":
            guard
                let tileSetName = attributeDict["name"],
                let firstgid = attributeDict["firstgid"] else {
                    print(
                        "SKTiledParser: (warning) invalid tileset definition at " +
                        "[\(parser.lineNumber)]; tileset definition will be skipped")
                    return
            }

            // Update the state of the parser so that we can parse all tile definitions.
            self.currentTileSet = SKTileSet()
            self.currentTileSet?.type = self.orientation
            self.currentStartingId = Int(firstgid)

        case "tile":
            if self.currentTileSet != nil {
                // If the current tileset isn't nil, we're about to parse the tile definitions of
                // a tileset.
                guard let id = attributeDict["id"] else {
                    print(
                        "SKTiledParser: (warning) missing property 'id' on tile element at " +
                        "[\(parser.lineNumber)]; tile definition will be skipped")
                    return
                }

                // Update the state of the parser so that we can parse the current tile definition.
                self.currentTileAttributes = TileAttributes()
                self.currentTileAttributes!.id = currentStartingId! + Int(id)!
            } else {
                // Otherwise, we're parsing the a layer definition.
                defer {
                    // Compute the position of the next tile to place.
                    if self.currentPosition.x == self.width - 1 {
                        self.currentPosition.x = 0
                        self.currentPosition.y -= 1
                    } else {
                        self.currentPosition.x += 1
                    }
                }

                guard let id = attributeDict["gid"] else {
                    print(
                        "SKTiledParser: (warning) missing property 'gid' on tile element at " +
                            "[\(parser.lineNumber)]; tile at position (\(self.currentPosition.x), " +
                        "\(self.currentPosition.y)) won't be placed")
                    return
                }

                // If the parsed gid is 0, there's no tile to place.
                if id == "0" {
                    return
                }

                guard let (tileGroup, tileSet) = self.tileGroups[Int(id)!] else {
                    print(
                        "SKTiledParser: (warning) unassigned tile gid at " +
                            "[\(parser.lineNumber)]; tile at position (\(self.currentPosition.x), " +
                        "\(self.currentPosition.y)) won't be placed")
                    return
                }

                // Create a new tilemap if we're placing the first tile.
                if self.currentTileMap == nil {
                    self.currentTileMap = SKTileMapNode(
                        tileSet: tileSet,
                        columns: self.width,
                        rows: self.height,
                        tileSize: self.tileSize)

                    // Set the name of the tilemap node if we could parse it.
                    self.currentTileMap!.name = self.currentLayerAttributes?.name

                    // Apply the layer offset (if we could parse it) on the tilemap position.
                    if let offsetX = self.currentLayerAttributes?.offsetX {
                        self.currentTileMap!.position.x = CGFloat(offsetX)
                    }
                    if let offsetY = self.currentLayerAttributes?.offsetY {
                        self.currentTileMap!.position.y = CGFloat(-offsetY)
                    }
                }

                // Make sure the tileset of the current tilemap matches that of the given tile
                // definition.
                assert(
                    self.currentTileMap!.tileSet == tileSet,
                    "all tiles of a tilemap should come from the same tileset.")

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
                        print(
                            "SKTiledParser: (warning) missing or invalid property 'source' on " +
                            "image element at [\(parser.lineNumber)]; texture will be skipped")
                        return
            }

            self.currentTileAttributes?.texture = SKTexture(
                imageNamed: self.texturesNamespace + textureName)

        case "property":
            guard
                let name = attributeDict["name"],
                let value = attributeDict["value"] else {
                    print(
                        "SKTiledParser: (warning) failed to parse custom property at " +
                        "[\(parser.lineNumber)]; property will be ignored")
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
                print("SKTiledParser: (warning) ignored custom property at [\(parser.lineNumber)]")
            }

        case "layer":
            self.currentLayerAttributes = LayerAttributes()

            if let name = attributeDict["name"] {
                self.currentLayerAttributes!.name = name
            }

            if let offsetX = attributeDict["offsetx"] {
                self.currentLayerAttributes!.offsetX = Int(offsetX)
            }

            if let offsetX = attributeDict["offsety"] {
                self.currentLayerAttributes!.offsetY = Int(offsetX)
            }

        // TODO: Handle tile offsets, animations and objects
        case "tileoffset", "animation", "frame", "objectgroup", "object":
            print(
                "SKTiledParser: (warning) ignored element '\(elementName)' [\(parser.lineNumber)]")

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?) {

        switch elementName {
        case "tileset":
            // Register the parsed tileSet.
            self.tileSets.append(self.currentTileSet!)

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
                    print(
                        "SKTiledParser: (warning) undefined tile texture; tile definition will " +
                        "be skipped")
                    return
                }

                // Create the tile group and add it to the tileset.
                let tileDefinition = SKTileDefinition(texture: texture)
                tileDefinition.userData = NSMutableDictionary(dictionary: tileAttributes.userData)

                let tileGroup = SKTileGroup(tileDefinition: tileDefinition)
                self.currentTileSet!.tileGroups.append(tileGroup)

                self.tileGroups[tileAttributes.id!] = (tileGroup, self.currentTileSet!)
            }

        case "layer":
            // Register the parsed tilemap.
            self.tileMaps.append(self.currentTileMap!)

            // Reset the state of the parser.
            self.currentLayerAttributes = nil
            self.currentTileMap = nil
            self.currentPosition = (0, self.height - 1)

        default:
            break
        }
    }

}
