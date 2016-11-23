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
        let parser = SKTiledParser(texturesNamespace: "Tiles/")

        guard let layout = parser.loadLayout(fromFileNamed: "tilemap") else {
            return
        }

        layout.baseLayer.position.x = view.frame.width / 2
        layout.baseLayer.position.y = view.frame.height / 2
        self.addChild(layout.baseLayer)
    }

}
