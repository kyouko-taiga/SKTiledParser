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
The texture of the tilesets are read from tile atlases that should be named after the name of your tileset within the `.tmx` file.
Individual tiles from that atlas are expected to have the same name as the files used in Tiled.

Let's say I have a tileset named `Terrain` in Tiled, with two tiles: `grass` and `rock`.
Then, I should create a sprite atlas called `Terrain` with two tile groups named respectively `grass` and `rock`.

The most convenient setup is to first generate your sprite atlases,
and then create your tilesets in Tiled using references to the files in your asset catalog.

The Xcode project is a usage example.
