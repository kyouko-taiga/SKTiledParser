# SKTiledParser

## Overview
A simple parser that can creates Apple Spritekit's `SKTileMapNode` from a `.tmx` file (created in [Tiled](www.mapeditor.org)).

The whole project is written with Swift 3.

## Motivation
Spritekit's `SKTileMapNode` is a nice addition to the Apple's framework,
but I find Xcode's tile editor not as good as the largely more popular Tiled editor.
I sought for a solution that would leverage `SKTileMapNode` while being able to import resources from Tiled,
but failed to find something that suited my needs.
As a result, I decided to rework Tom Linthwaite's [SKTilemap](https://github.com/TomLinthwaite/SKTilemap) project so that I could generate `SKTileMapNode` and `SKTileSet` from `.tmx` files.

## Usage
Simply drag and drop `SKTiledParser.swift` to your project to import the code.

Then, create an instance of SKTiledParser, and load your `.tmx` file with `loadLayout(fromFileNamed:)`.
Each layer from your file will be transformed into an `SKTileMapNode`,
and made children of a single "layout" the method will return.
You can then access the root node of this layout to insert the tilemaps in your scene.

```swift
let parser = SKTiledParser()
let layout = parser.loadLayout(fromFileNamed: "tilemap")
scene.addChild(layout!.rootNode)
```

It will not only create the tilemap nodes, but also the `SKTileSet` from which the tiles will be displayed.

The Xcode project shows a working example.

### Locating textures
The textures of the tilesets are read from your assets.
Note that for that mechanism to work, tile images referenced within your `.tmx` file are expected to be named after your assets name.
Only the base name of the file (without extension) matters.

For instance, let's say I defined two image sets in my asset catalog, named `grass` and `rock`.
Then Tiled should reference them by files respectively named `path/to/somewhere/grass.png` and `path/to/somewhere/rock.png` (the extension doesn't matter, it could very well be `.jpg` instead)

Since the texture lookup is done by `SKTexture.init(imageNamed:)`, you can seamlessly use sprite atlases.

The most convenient setup is to first generate your sprite atlases,
and then create your tilesets in Tiled using references to the files in your asset catalog.

Finally, if like me you like to keep your things tidy in you asset catalog, you can use namespaces.
Initialize `SKTiledParser` with `init(texturesNamespace:)` to specify the namespace that should be prepended when searching for textures.