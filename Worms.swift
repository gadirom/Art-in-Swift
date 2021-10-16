
// Just copy and paste the code into a blank playground template
// in Swift Playgrounds app on an iPad or a Mac
// !!! Turn off Enable Results in the settings, otherwise you'll get an error !!!
// Created by Roman Gaditskiy: https://GitHub.com/gadirom/Art-in-Swift

import SwiftUI
import PlaygroundSupport
import Combine
import CoreGraphics

let context = CIContext(options:nil)

let blurRadius = 10.0

var contentFrame = CGRect()

let constrainStickMinLength = false
let pointSize = CGSize(width: 3, height: 3)
let frameScale: CGFloat = 20
let power: CGFloat = 1
var width: CGFloat = 0.005
var segment: CGFloat = 0
let gravity: CGFloat = 0
let speed: CGFloat = 0.1
var friction: CGFloat = 1

let numberOfWorms = 100
let segmentsInWorm = 10
let wormSpeed: CGFloat = 1

var points: [Point] = []
var sticks: [Stick] = []
var startTime = Date() 

func generateWorms(){
    _ = (0..<numberOfWorms).map{ w in
        let pos = CGPoint(x: CGFloat.random(in: 0..<contentFrame.maxX/2) + contentFrame.midX/2, 
                          y: CGFloat.random(in: 0..<contentFrame.maxY/2) + contentFrame.midY/2)
        let speed = CGPoint(x: CGFloat.random(in: -1...1) * wormSpeed, y: CGFloat.random(in: -1...1) * wormSpeed)
        points.append(Point(pos: pos, prevPos: speed, locked:true))
        var color = CGColor.random()
        _ = (0..<segmentsInWorm).map{ seg in
            let pos = CGPoint(x: CGFloat.random(in: 0..<contentFrame.maxX/2) + contentFrame.midX/2, 
                              y: CGFloat.random(in: 0..<contentFrame.maxY/2) + contentFrame.midY/2)
            points.append(Point(pos: pos, prevPos: pos))
            let p = w * (segmentsInWorm+1) + seg
            
            color = color.copy(alpha: (CGFloat(segmentsInWorm)-sqrt(CGFloat(seg)))/CGFloat(segmentsInWorm))!
            sticks.append(Stick(pointA: p, pointB: p+1, color: color))
        }
    }
    //sticks.shuffle()
}

extension CGColor{
    static func random()->CGColor {
        let red = CGFloat.random(in: 0.5...1)
        let green = CGFloat.random(in: 0.5...1)
        let blue = CGFloat.random(in: 0.5...1)
        return CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
    
}

func simulateWorms(time: CGFloat){
    DispatchQueue.concurrentPerform(iterations: numberOfWorms){
        var worm = points[$0*(segmentsInWorm+1)]
        
        worm.pos += worm.prevPos
        
        worm.prevPos.x -= pow(frameScale / (contentFrame.maxX-worm.pos.x), power)
        worm.prevPos.y -= pow(frameScale / (contentFrame.maxY-worm.pos.y), power)
        
        worm.prevPos.x += pow(frameScale / (worm.pos.x), power)
        worm.prevPos.y += pow(frameScale / (worm.pos.y), power)
        
            //ordinary bouncing
        /*if worm.pos.x > contentFrame.maxX || worm.pos.x < 0 { worm.prevPos.x *= -1 }
        if worm.pos.y > contentFrame.maxY || worm.pos.y < 0 { worm.prevPos.y *= -1 }*/
        points[$0*(segmentsInWorm+1)] = worm
    }
 }

func simulate(time: CGFloat) {
    DispatchQueue.concurrentPerform(iterations: points.count){
        var point = points[$0]
        if !point.locked{
            let prevPos = point.pos
            point.pos = point.pos +
                (point.pos - point.prevPos) * friction + 
                (CGSize(width: 0, height: 1) * gravity * time * time)
            point.prevPos = prevPos
        }
        points[$0] = point
    }
    
    for i in 0...0{ // try increasing the range for more uniform results
        sticks = sticks.map { stick in
        var stickCentre = (points[stick.pointA].pos + points[stick.pointB].pos) / 2.0
        var stickDir = (points[stick.pointA].pos - points[stick.pointB].pos).normalized()
        var length = (points[stick.pointA].pos - points[stick.pointB].pos).length()
        
        if length != segment { 
            if (!points[stick.pointA].locked)
            {
                points[stick.pointA].pos = stickCentre + stickDir * segment / 2
            }
            if (!points[stick.pointB].locked)
            {
                points[stick.pointB].pos = stickCentre - stickDir * segment / 2
            }
        }
        return stick
    }
    } 
}

struct Point {
        var pos: CGPoint = CGPoint()
        var prevPos: CGPoint = CGPoint()
        var locked = false
    }

struct Stick {
        init (pointA: Int, pointB: Int, color: CGColor){
            self.pointA = pointA
            self.pointB = pointB
            self.origLength = segment
            self.color = color
        }
        
        var pointA: Int
        var pointB: Int
        var length: CGFloat{ (points[pointB].pos-points[pointA].pos).length() }
        var origLength: CGFloat
        var color: CGColor
    }

func drawPoint(ctx: UIGraphicsRendererContext, origin: CGPoint, size: CGSize, locked: Bool){
    let rectangle = CGRect(origin: origin - (size / 2), size: size)
    
    ctx.cgContext.setFillColor(locked ? UIColor.white.cgColor : UIColor.red.cgColor)
    ctx.cgContext.setStrokeColor(UIColor.clear.cgColor)
    //ctx.cgContext.setLineWidth(5*width)
    
    ctx.cgContext.addEllipse(in: rectangle)
    ctx.cgContext.drawPath(using: .fillStroke)
}

func drawImage(size: CGSize, points: [Point], sticks: [Stick]) -> UIImage {
        
    let renderer = UIGraphicsImageRenderer(size: size)
    
    let img = renderer.image { ctx in
        
        
        var maxLength = size.length()
        
        _ = sticks.map{ stick in
            var lineWidth = width * maxLength / stick.length
            lineWidth = lineWidth < pointSize.width ? lineWidth : pointSize.width
            ctx.cgContext.setLineWidth(lineWidth)
            ctx.cgContext.setStrokeColor(stick.color)
            ctx.cgContext.move(to: points[stick.pointA].pos)
            ctx.cgContext.addLine(to: points[stick.pointB].pos)
            
            ctx.cgContext.drawPath(using: .stroke)
        }
            //Draw heads
        /*for i in 0..<numberOfWorms{ 
            var point = points[i*(segmentsInWorm+1)]
            drawPoint(ctx: ctx, origin: point.pos, size: pointSize, locked: point.locked)
        }*/
    }
    
    return img
}

struct ContentView: View {
    
    init (refreshRate: Double){
        self.refreshInterval = 1 / refreshRate
        self.timer = Timer.publish(every: refreshInterval, tolerance: 0, on: .current, in: .common).autoconnect()
    }
    
    var timer: Publishers.Autoconnect<Timer.TimerPublisher>
    
    let refreshInterval: Double
    
    @State var drawnImage = UIImage()
    @State var fric: CGFloat = 0.5
    @State var seg: CGFloat = 0
    @State var wid: CGFloat = 0.01
    
    @State var simulation = true
    
    var body: some View{
        VStack{ 
            ZStack{
                Image(uiImage: drawnImage)
                Color.clear.contentShape(Rectangle())
                    .onAppear(){
                        generateWorms()
                    }
                    .onTapGesture(count: 2){
                        simulation.toggle()
                    }
        }
        .onReceive(timer) { time in
            friction = fric * 2
            segment = seg * 500
            width = wid
            if simulation{ 
                let t = CGFloat(time.compare(startTime).rawValue)*speed
                simulateWorms(time: t)
                simulate(time: t)
            }else{startTime = time}
                drawnImage = drawImage(size: contentFrame.size, points: points, sticks: sticks)
            }
        .overlay(
            GeometryReader { geo in
                Color.clear
                    .preference(key: framePreferenceKey.self, value: geo.frame(in:.global))
            }.onPreferenceChange(framePreferenceKey.self){contentFrame = $0}
        )
            Slider(value: $fric)
            Slider(value: $seg)
            Slider(value: $wid)
        }
    }
}

struct framePreferenceKey: PreferenceKey {
    static var defaultValue = CGRect()
    
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension CGPoint{
    static func +(lhs: CGPoint, rhs: CGSize) -> CGPoint{
        CGPoint(
            x: lhs.x + rhs.width,
            y: lhs.y + rhs.height
        )
    }
    
    static func +(lhs: CGPoint, rhs: CGPoint) -> CGPoint{
        CGPoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }
    
    static func +=(lhs: inout CGPoint, rhs: CGPoint) {
        lhs = CGPoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }
    
    static func +=(lhs: inout CGPoint, rhs: CGSize) {
        lhs = CGPoint(
            x: lhs.x + rhs.width,
            y: lhs.y + rhs.height
        )
    }
    
    static func -(lhs: CGPoint, rhs: CGSize) -> CGPoint{
        CGPoint(
            x: lhs.x - rhs.width,
            y: lhs.y - rhs.height
        )
    }
    
    static func -(lhs: CGPoint, rhs: CGPoint) -> CGSize{
        CGSize(
            width: lhs.x - rhs.x,
            height: lhs.y - rhs.y
        )
    }
    
    static func  /(lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs,
                y: lhs.y / rhs)
    }
    
    func length() -> CGFloat{
        sqrt(x * x + y * y)
    }
    
    func normalized() -> CGPoint {
        let len = length()
        return len>0 ? self / len : .zero
    }
}

extension CGSize{
    func length() -> CGFloat{
        sqrt(width * width + height * height)
    }
    
    func normalized() -> CGSize {
        let len = length()
        return len>0 ? self / len : .zero
    }
    
    mutating func rotate(_ a: CGFloat) {
        
        let x = width * cos(a) - height * sin(a)
        let y = width * sin(a) + height * cos(a)
        
        self = CGSize(width: x, height: y)
        
    }
    
    mutating func randomizeAngle(_ rnd: CGFloat) {
        
        let a = CGFloat.random(in: -rnd...rnd)
        
        self.rotate(a)
        
    }
    
    static func +=(lhs: inout CGSize, rhs: CGSize) {
        lhs = CGSize(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }
    
    static func +(lhs: CGSize, rhs: CGSize) -> CGSize{
        CGSize(
            width: lhs.width + rhs.width,
            height: lhs.height + rhs.height
        )
    }
    
    static func -(lhs: CGSize, rhs: CGSize) -> CGSize{
        CGSize(
            width: lhs.width - rhs.width,
            height: lhs.height - rhs.height
        )
    }
    
    static func  *(lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs,
               height: lhs.height * rhs)
    }
    
    static func  +(lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width + rhs,
               height: lhs.height + rhs)
    }
    
    static func  /(lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width / rhs,
               height: lhs.height / rhs)
    }
}


PlaygroundPage.current.setLiveView(ContentView(refreshRate: 120))
