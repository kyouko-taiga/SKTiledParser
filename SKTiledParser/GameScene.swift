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

        guard let layout = parser.loadLayout(fromFileNamed: "tilemap") else {
            return
        }

        layout.rootNode.position.x = view.frame.width / 2
        layout.rootNode.position.y = view.frame.height / 2
        self.addChild(layout.rootNode)
    }

}
