//
//  GameScene.swift
//  SKTiledParser
//
//  Created by Dimitri Racordon on 17.11.16.
//
//

import SpriteKit


class GameScene: SKScene {

    override func didMove(to view: SKView) {
        let parser = SKTiledParser(atlasPrefix: "Tiles/")
        for tileMap in parser.loadTileMaps(fromFileNamed: "tilemap") {
            tileMap.position.x = view.frame.width / 2
            tileMap.position.y = view.frame.height / 2
            self.addChild(tileMap)
        }
    }

}
