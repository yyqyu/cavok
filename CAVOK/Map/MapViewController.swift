//
//  MapViewController.swift
//  CAVOK
//
//  Created by Juho Kolehmainen on 04.09.16.
//  Copyright © 2016 Juho Kolehmainen. All rights reserved.
//

import UIKit
import CoreLocation
import PromiseKit

class MapViewController: UIViewController {
    
    @IBOutlet weak var status: UITextField!
    
    internal var mapView: WhirlyGlobeViewController!

    fileprivate let modules = Modules()
    
    fileprivate var module: MapModule!
    
    fileprivate var components: [NSObject: MaplyComponentObject] = [:]
    
    private var locationManager: LocationManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        mapView = WhirlyGlobeViewController()
        mapView.delegate = self
        
        view.insertSubview(mapView.view, at: 0)
        mapView.view.frame = view.bounds
        addChildViewController(mapView)
        
        mapView.keepNorthUp = true
        mapView.frameInterval = 2 // 30fps
        mapView.threadPerLayer = true
        mapView.autoMoveToTap = false
        
        if let (center, height) = LastSession.load() {
            mapView.height = height
            mapView.setPosition(center)
        }
        
        if let basemap = UserDefaults.standard.string(forKey: "basemapURL"), let url = URL(string: basemap) {
            TileJSONLayer().load(url: url).then { layer in
                self.mapView.add(layer)
            }.catch { e in
                print(e)
            }
        }
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(MapViewController.enteredBackground(notification:)),
                                               name: .UIApplicationDidEnterBackground,
                                               object: nil
        )
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(MapViewController.enteredForeground(notification:)),
                                               name: .UIApplicationWillEnterForeground,
                                               object: nil
        )
        
        locationManager = LocationManager(
            fulfill: userLocationChanged,
            reject: { error in
                self.clearComponents(ofType: UserMarker.self)
            })
        locationManager.requestLocation()
        
        module = modules.loadModule(index: 0, delegate: self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func enteredBackground(notification: Notification) {
        LastSession.save(center: mapView.getPosition(), height: mapView.getHeight())
    }
    
    func enteredForeground(notification: Notification) {
        locationManager.requestLocation()
    }

    func userLocationChanged(coordinate: MaplyCoordinate) {
        clearComponents(ofType: UserMarker.self)
        
        let userLocation = UserMarker(coordinate: coordinate)
        if let objects = mapView.addScreenMarkers([userLocation], desc: nil) {
            addComponents(key: userLocation, value: objects)
        }
        
        let bbox = mapView.getCurrentExtents()
        let height = LastSession.load()?.height
        if height == nil || !bbox.inside(coordinate) {
            mapView.height = height ?? 0.2
            mapView.animate(toPosition: coordinate, time:0.5)
            
            module.configure(userLocation: userLocation.loc)
        }
    }
    
    @IBAction func resetRegion(sender: UIButton) {
        module.configure(userLocation: nil)
    }
}

// MARK: - MapDelegate
extension MapViewController : MapDelegate {

    func setStatus(error: Error) {
        switch error {
        case let Weather.error(msg):
            setStatus(text: msg)
        default:
            print(error)
            setStatus(text: error.localizedDescription)
        }
        
    }
    
    func setStatus(text: String?, color: UIColor = UIColor.red) {
        if let text = text {
            DispatchQueue.main.async {
                self.status.textColor = color
                self.status.text = "\(text)"
            }
        }
    }
    
    func clearAnnotations(ofType: MaplyAnnotation.Type?) {
        if let ofType = ofType, let annotations = mapView.annotations() {
            annotations.forEach { annotation in
                if type(of: annotation) == ofType {
                    mapView.removeAnnotation(annotation as! MaplyAnnotation)
                }
            }
        } else {
            mapView.clearAnnotations()
        }
    }

    func findComponent(ofType: NSObject.Type) -> NSObject? {
        return components.keys.filter { $0.isKind(of: ofType) }.first
    }
    
    func addComponents(key: NSObject, value: MaplyComponentObject) {
        components[key] = value
    }
    
    func clearComponents(ofType: NSObject.Type?) {
        if let ofType = ofType {
            let matching = components
                .filter { type(of: $0.key) == ofType }
                .flatMap { components.removeValue(forKey: $0.key) }
            mapView.remove(matching)
        } else {
            mapView.remove([MaplyComponentObject](components.values))
            components.removeAll()
        }
    }
}

// MARK: - UITextFieldDelegate
extension MapViewController: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField == self.status {
            module.refresh()
        }
        return false
    }
}

// MARK: - WhirlyGlobeViewControllerDelegate
extension MapViewController: WhirlyGlobeViewControllerDelegate {
    func globeViewController(_ view: WhirlyGlobeViewController, didTapAt coord: MaplyCoordinate) {
        view.clearAnnotations()
        
        module.didTapAt(coord: coord)
    }
}
