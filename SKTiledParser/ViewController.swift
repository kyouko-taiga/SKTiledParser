//
//  ViewController.swift
//  SKTiledParser
//
//  Created by Dimitri Racordon on 17.11.16.
//
//

import Cocoa
import SpriteKit


class ViewController: NSViewController {

    @IBOutlet var skView: SKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if let view = self.skView {
            // Create and present the game scene.
            let scene = GameScene(size: view.frame.size)
            view.presentScene(scene)
            
            view.ignoresSiblingOrder = true
            
            view.showsFPS = true
            view.showsNodeCount = true
        }
    }
}

