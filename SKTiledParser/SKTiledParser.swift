//
//  SKTiledParser
//  SKTiledParser.swift
//
//  Created by Dimitri Racordon on 17.11.16.
//
//

import SpriteKit


// MARK: TileAttributes

struct TileAttributes {
    var id: Int?
    var texture: SKTexture?
    var userData = [String: Any]()
}


// MARK: SKTiledParser

class SKTiledParser : NSObject, XMLParserDelegate {

    // MARK: Properties

    public let atlasPrefix: String

    private var errorMessage = ""

    private var width  = 0
    private var height = 0
    private var tileSize = CGSize.zero
    private var orientation: SKTileSetType = .isometric

    private var tileMaps = [SKTileMapNode]()
    private var tileSets = [SKTileSet]()

    private var tileGroups = [Int: (SKTileGroup, SKTileSet)]()

    private var currentAtlas: SKTextureAtlas?
    private var currentTileSet: SKTileSet?
    private var currentStartingId: Int?
    private var currentTileAttributes: TileAttributes?

    private var currentTileMap: SKTileMapNode?
    private var currentPosition: (x: Int, y: Int) = (0, 0)

    // MARK: Functions

    init(atlasPrefix: String = "") {
        self.atlasPrefix = atlasPrefix
    }

    /** Creates an SKtileMapNode for each layer defined in a .tmx tilemap file. */
    func loadTileMaps(fromFileNamed filename: String) -> [SKTileMapNode] {

        guard let url = Bundle.main.url(forResource: filename, withExtension: ".tmx") else {
            print("SKTiledParser: (error) tilemap '\(filename)' couldn't be found")
            return []
        }

        let data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch let error {
            print("SKTiledParser: \(error.localizedDescription)")
            return []
        }

        let parser = XMLParser(data: data!)
        parser.delegate = self
        self.errorMessage = "couldn't parse \(filename)"

        if parser.parse() {
            return self.tileMaps
        }

        print("SKTiledParser: (error) " + self.errorMessage)
        return []
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
                        "SKTiledParser: (warning) unsupported orientation '\(elementName)', " +
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
            self.currentAtlas = SKTextureAtlas(named: "\(self.atlasPrefix)\(tileSetName)")
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
                defer {
                    // Compute the position of the next tile to place.
                    if self.currentPosition.x == self.width - 1 {
                        self.currentPosition.x = 0
                        self.currentPosition.y -= 1
                    } else {
                        self.currentPosition.x += 1
                    }
                }

                // Otherwise, we're parsing the a layer definition.
                guard let id = attributeDict["gid"] else {
                    print(
                        "SKTiledParser: (warning) missing property 'gid' on tile element at " +
                            "[\(parser.lineNumber)]; tile at position (\(self.currentPosition.x), " +
                        "\(self.currentPosition.y)) won't be placed")
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

            self.currentTileAttributes?.texture = self.currentAtlas?.textureNamed(textureName)

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
                tileAttributes.userData[name] = value
            } else {
                // TODO: Handle custom properties on maps, layers, objectgroups and objects.
                print("SKTiledParser: (warning) ignored custom property at [\(parser.lineNumber)]")
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
            self.currentAtlas = nil
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
            self.currentTileMap = nil
            self.currentPosition = (0, self.height - 1)
            
        default:
            break
        }
    }
    
}
